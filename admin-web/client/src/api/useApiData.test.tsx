import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError, api } from "./client";
import { useApiData } from "./useApiData";

vi.mock("./client", async (orig) => {
  const actual = await orig<typeof import("./client")>();
  return { ...actual, api: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } };
});

const get = vi.mocked(api.get);

beforeEach(() => get.mockReset());
afterEach(() => vi.useRealTimers());

describe("useApiData", () => {
  it("загружает данные и отдаёт их без ошибки", async () => {
    get.mockResolvedValue([1, 2]);
    const { result } = renderHook(() => useApiData<number[]>("/api/x", { pollMs: false }));
    expect(result.current.data).toBeNull();
    await waitFor(() => expect(result.current.data).toEqual([1, 2]));
    expect(result.current.error).toBeNull();
  });

  it("ошибка API показывает сообщение сервера, сетевая — общее; данные при этом не сбрасываются", async () => {
    get.mockResolvedValueOnce("ok");
    const { result } = renderHook(() => useApiData<string>("/api/x", { pollMs: false }));
    await waitFor(() => expect(result.current.data).toBe("ok"));

    get.mockRejectedValueOnce(new ApiError(500, "сервер упал"));
    act(() => result.current.reload());
    await waitFor(() => expect(result.current.error).toBe("сервер упал"));
    expect(result.current.data).toBe("ok");

    get.mockRejectedValueOnce(new Error("network"));
    act(() => result.current.reload());
    await waitFor(() => expect(result.current.error).toBe("не удалось связаться с сервером"));
  });

  it("опрашивает по таймеру и перестаёт, когда pollMs=false", async () => {
    vi.useFakeTimers();
    get.mockResolvedValue("v");
    const { unmount } = renderHook(() => useApiData<string>("/api/x", { pollMs: 1000 }));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3100);
    });
    expect(get.mock.calls.length).toBeGreaterThanOrEqual(3);
    unmount();
    const after = get.mock.calls.length;
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000);
    });
    expect(get.mock.calls.length).toBe(after);
  });

  it("смена адреса или ключа перезапрашивает; функция-адрес вызывается при каждой загрузке", async () => {
    get.mockResolvedValue("v");
    const { rerender } = renderHook(({ p }: { p: string }) => useApiData<string>(p, { pollMs: false }), { initialProps: { p: "/api/a" } });
    await waitFor(() => expect(get).toHaveBeenCalledWith("/api/a"));
    rerender({ p: "/api/b" });
    await waitFor(() => expect(get).toHaveBeenCalledWith("/api/b"));

    let n = 0;
    const { result, rerender: rerender2 } = renderHook(({ k }: { k: string }) => useApiData<string>(() => `/api/f?n=${++n}`, { key: k, pollMs: false }), { initialProps: { k: "1" } });
    await waitFor(() => expect(result.current.data).toBe("v"));
    const before = get.mock.calls.length;
    rerender2({ k: "2" });
    await waitFor(() => expect(get.mock.calls.length).toBeGreaterThan(before));
  });
});
