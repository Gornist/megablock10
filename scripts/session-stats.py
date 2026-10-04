#!/usr/bin/env python3
"""
Анализ расхода токенов одной сессии Claude Code по её транскрипту JSONL.
Считает инструменты, токены, изображения, правки, sleep'ы в Bash.

Вызов:
  scripts/session-stats.py <путь.jsonl>
  scripts/session-stats.py --session <id>
  scripts/session-stats.py <путь.jsonl> --json
"""

import json
import sys
import re
from pathlib import Path
from datetime import datetime
from collections import Counter, defaultdict
from typing import Optional, Dict, Any, List


def find_session_file(session_id: str) -> Optional[str]:
    """Ищет файл сессии по ID в ~/.claude/projects/*/"""
    projects_dir = Path.home() / '.claude' / 'projects'
    if not projects_dir.exists():
        return None

    for proj_dir in projects_dir.iterdir():
        if not proj_dir.is_dir():
            continue
        jsonl_file = proj_dir / f"{session_id}.jsonl"
        if jsonl_file.exists():
            return str(jsonl_file)

    return None


def parse_args() -> tuple:
    """Парсит аргументы. Возвращает (path, json_output)"""
    json_output = False
    path = None

    i = 0
    while i < len(sys.argv) - 1:
        i += 1
        arg = sys.argv[i]

        if arg == '--json':
            json_output = True
        elif arg == '--session':
            i += 1
            session_id = sys.argv[i]
            path = find_session_file(session_id)
            if not path:
                print(f"error: сессия {session_id} не найдена", file=sys.stderr)
                sys.exit(1)
        else:
            path = arg

    if not path:
        print("usage: session-stats.py <путь.jsonl> | --session <id>", file=sys.stderr)
        sys.exit(1)

    return path, json_output


def extract_tool_names(content: List[Dict]) -> List[str]:
    """Извлекает имена инструментов из блоков контента."""
    names = []
    for block in content:
        if isinstance(block, dict):
            if block.get('type') == 'tool_use':
                name = block.get('name')
                if name:
                    names.append(name)
    return names


def extract_bash_commands(tool_input: Any) -> List[str]:
    """Извлекает команды Bash из input инструмента."""
    commands = []
    if isinstance(tool_input, dict) and 'command' in tool_input:
        cmd = tool_input['command']
        if isinstance(cmd, str):
            # Парсим цепочку команд, пропускаем cd
            parts = re.split(r'\s*&&\s*', cmd)
            for part in parts:
                part = part.strip()
                if part and not part.startswith('cd '):
                    commands.append(part.split()[0] if part.split() else '')
    return commands


def extract_read_size(tool_result: Any) -> int:
    """Извлекает размер результата Read инструмента (количество символов)."""
    if isinstance(tool_result, str):
        return len(tool_result)
    elif isinstance(tool_result, dict):
        # Результат может быть в 'content' или прямо в output
        content = tool_result.get('content')
        if isinstance(content, str):
            return len(content)
        elif isinstance(content, list):
            total = 0
            for block in content:
                if isinstance(block, dict) and 'text' in block:
                    total += len(block['text'])
            return total
    return 0


def count_image_blocks(blocks: List[Dict]) -> int:
    """Считает количество блоков с изображениями в результатах инструментов."""
    count = 0
    for block in blocks:
        if isinstance(block, dict) and block.get('type') == 'image':
            count += 1
    return count


def process_jsonl(filepath: str) -> Dict[str, Any]:
    """Обрабатывает JSONL файл и собирает статистику."""
    stats = {
        'duration_start': None,
        'duration_end': None,
        'assistant_count': 0,
        'seen_msg_ids': set(),
        'total_input_tokens': 0,
        'total_cache_read_tokens': 0,
        'total_cache_creation_tokens': 0,
        'total_output_tokens': 0,
        'cache_read_per_turn': [],
        'tool_calls': Counter(),
        'bash_top_commands': Counter(),
        'read_calls': 0,
        'read_total_size': 0,
        'image_blocks': 0,
        'python_edits': 0,
        'sleep_calls': 0,
    }

    # Кэш для отображения tool_use_id -> tool_name
    tool_use_id_to_name = {}

    try:
        with open(filepath, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                obj_type = obj.get('type')
                timestamp = obj.get('timestamp')

                # Обновляем диапазон времени
                if timestamp:
                    try:
                        ts = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                        if stats['duration_start'] is None:
                            stats['duration_start'] = ts
                        stats['duration_end'] = ts
                    except (ValueError, AttributeError):
                        pass

                if obj_type == 'assistant':
                    msg = obj.get('message', {})
                    msg_id = msg.get('id')

                    if msg_id and msg_id not in stats['seen_msg_ids']:
                        stats['seen_msg_ids'].add(msg_id)
                        stats['assistant_count'] += 1

                        # Собираем токены (один раз на message.id)
                        usage = msg.get('usage', {})
                        stats['total_input_tokens'] += usage.get('input_tokens', 0)
                        stats['total_cache_read_tokens'] += usage.get('cache_read_input_tokens', 0)
                        stats['total_cache_creation_tokens'] += usage.get('cache_creation_input_tokens', 0)
                        stats['total_output_tokens'] += usage.get('output_tokens', 0)

                        cache_read = usage.get('cache_read_input_tokens', 0)
                        if cache_read > 0:
                            stats['cache_read_per_turn'].append(cache_read)

                    # Собираем инструменты из всех блоков в этом сообщении
                    content = msg.get('content', [])
                    tool_names = extract_tool_names(content)
                    for name in tool_names:
                        stats['tool_calls'][name] += 1

                        # Ищем input этого инструмента в content
                        for block in content:
                            if (isinstance(block, dict) and
                                block.get('type') == 'tool_use' and
                                block.get('name') == name):
                                tool_id = block.get('id')
                                tool_input = block.get('input', {})

                                # Сохраняем соответствие tool_use_id -> name
                                if tool_id:
                                    tool_use_id_to_name[tool_id] = name

                                # Bash команды
                                if name == 'Bash':
                                    cmds = extract_bash_commands(tool_input)
                                    for cmd in cmds:
                                        if cmd:
                                            stats['bash_top_commands'][cmd] += 1
                                            if cmd == 'sleep':
                                                stats['sleep_calls'] += 1
                                    raw = tool_input.get('command', '') if isinstance(tool_input, dict) else ''
                                    if re.search(r'python3?\s+-\s*<<', raw):
                                        stats['python_edits'] += 1

                                break

                elif obj_type == 'user':
                    # Ищем tool_result в контенте user
                    msg = obj.get('message', {})
                    content = msg.get('content', [])

                    for block in content:
                        if not isinstance(block, dict):
                            continue

                        if block.get('type') == 'tool_result':
                            tool_use_id = block.get('tool_use_id')
                            tool_name = tool_use_id_to_name.get(tool_use_id)
                            block_content = block.get('content')

                            # Read инструмент
                            if tool_name == 'Read':
                                stats['read_calls'] += 1
                                size = extract_read_size(block_content)
                                stats['read_total_size'] += size

                            # Ищем изображения в результатах
                            if isinstance(block_content, list):
                                for sub_block in block_content:
                                    if isinstance(sub_block, dict) and sub_block.get('type') == 'image':
                                        stats['image_blocks'] += 1

    except IOError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

    return stats


def format_output(stats: Dict[str, Any]) -> str:
    """Форматирует вывод статистики."""
    duration = ""
    if stats['duration_start'] and stats['duration_end']:
        diff = stats['duration_end'] - stats['duration_start']
        s = int(diff.total_seconds())
        duration = f"{s // 3600} ч {s % 3600 // 60} мин"

    cache_avg = 0
    cache_max = 0
    if stats['cache_read_per_turn']:
        cache_avg = sum(stats['cache_read_per_turn']) / len(stats['cache_read_per_turn'])
        cache_max = max(stats['cache_read_per_turn'])

    lines = []
    lines.append(f"Длительность: {duration}")
    lines.append(f"Ходов ассистента: {stats['assistant_count']}")
    lines.append(f"Токены: input={stats['total_input_tokens']:,} "
                f"cache_read={stats['total_cache_read_tokens']:,} "
                f"cache_creation={stats['total_cache_creation_tokens']:,} "
                f"output={stats['total_output_tokens']:,}")
    lines.append(f"Контекст за ход (cache_read): средний={cache_avg:,.0f} максимум={cache_max:,}")

    all_tools = sum(stats['tool_calls'].values())
    lines.append(f"Инструменты всего: {all_tools}")

    top_10_tools = stats['tool_calls'].most_common(10)
    if top_10_tools:
        lines.append("  Топ-10:")
        for name, count in top_10_tools:
            lines.append(f"    {name}: {count}")

    if stats['bash_top_commands']:
        top_8_bash = stats['bash_top_commands'].most_common(8)
        lines.append("  Bash топ-8 команд:")
        for cmd, count in top_8_bash:
            lines.append(f"    {cmd}: {count}")

    lines.append(f"Read: {stats['read_calls']} вызовов, {stats['read_total_size']:,} символов")
    lines.append(f"Изображения в результатах: {stats['image_blocks']}")
    lines.append(f"Bash с python-heredoc (python3 - <<): {stats['python_edits']}")
    lines.append(f"Bash с sleep: {stats['sleep_calls']}")

    return "\n".join(lines)


def format_json(stats: Dict[str, Any]) -> str:
    """Форматирует вывод в JSON."""
    output = {
        'duration_start': stats['duration_start'].isoformat() if stats['duration_start'] else None,
        'duration_end': stats['duration_end'].isoformat() if stats['duration_end'] else None,
        'assistant_turns': stats['assistant_count'],
        'tokens': {
            'input': stats['total_input_tokens'],
            'cache_read': stats['total_cache_read_tokens'],
            'cache_creation': stats['total_cache_creation_tokens'],
            'output': stats['total_output_tokens'],
        },
        'cache_per_turn': {
            'avg': sum(stats['cache_read_per_turn']) / len(stats['cache_read_per_turn']) if stats['cache_read_per_turn'] else 0,
            'max': max(stats['cache_read_per_turn']) if stats['cache_read_per_turn'] else 0,
        },
        'tools': {
            'total': sum(stats['tool_calls'].values()),
            'by_name': dict(stats['tool_calls'].most_common(10)),
        },
        'bash': {
            'top_commands': dict(stats['bash_top_commands'].most_common(8)),
            'sleep_calls': stats['sleep_calls'],
        },
        'read': {
            'calls': stats['read_calls'],
            'total_chars': stats['read_total_size'],
        },
        'images': stats['image_blocks'],
        'edits': stats['python_edits'],
    }

    return json.dumps(output, indent=2, ensure_ascii=False)


def main():
    filepath, json_output = parse_args()

    stats = process_jsonl(filepath)

    if json_output:
        print(format_json(stats))
    else:
        print(format_output(stats))


if __name__ == '__main__':
    main()
