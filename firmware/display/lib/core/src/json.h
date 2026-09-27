#pragma once
#include <cstddef>
#include <cstdint>

// Крошечный разбор JSON для команд звука (AUDIO_STATE, ANNOUNCE): без кучи и без библиотек — курсор по буферу. Разбирает
// ровно то, что шлёт сервер (объект с числами, логическими значениями, строками и массивами строк); остальное пропускает.
namespace mb10d {

class JsonCursor {
 public:
  JsonCursor(const char* s, size_t n) : p_(s), end_(s + n) {}

  // Объект: beginObject(), затем nextKey(key) до false; после ключа — значение одним из read*/skip().
  bool beginObject();
  bool nextKey(char* key, size_t cap);
  bool beginArray();
  // Следующий элемент массива есть (после beginArray и после каждого элемента).
  bool nextItem();

  // Строка с экранированием (\" \\ \/ \n \t \uXXXX → UTF-8). Длиннее cap-1 — ошибка.
  bool readString(char* out, size_t cap);
  bool readNumber(double& out);
  bool readBool(bool& out);
  bool skip();

  bool ok() const { return ok_; }

 private:
  void ws();
  bool lit(const char* word);
  const char* p_;
  const char* end_;
  bool ok_ = true;
  // «Следующий элемент — первый» на каждом уровне вложенности (объект в массиве и т. п.).
  static constexpr int kDepth = 8;
  bool first_[kDepth] = {true};
  int depth_ = 0;
  bool push();
  bool& first() { return first_[depth_ > 0 ? depth_ - 1 : 0]; }
};

// Строка в JSON: кавычки и экранирование; false — не влезло (out не дописан).
bool jsonAppendString(char* out, size_t cap, size_t& len, const char* s);

}  // namespace mb10d
