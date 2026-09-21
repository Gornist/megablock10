import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Pager } from "./Pager";

describe("Pager", () => {
  it("на первой странице «назад» недоступна, «вперёд» — пока есть записи", () => {
    const onPage = vi.fn();
    render(<Pager page={0} pageSize={50} total={120} onPage={onPage} />);
    expect((screen.getByText("← назад") as HTMLButtonElement).closest("button")!.disabled).toBe(true);
    fireEvent.click(screen.getByText("вперёд →"));
    expect(onPage).toHaveBeenCalledWith(1);
  });

  it("на последней странице «вперёд» недоступна, «назад» возвращает на предыдущую", () => {
    const onPage = vi.fn();
    render(<Pager page={2} pageSize={50} total={120} onPage={onPage} prevLabel="← новее" nextLabel="старше →" />);
    expect(screen.getByText("старше →").closest("button")!.disabled).toBe(true);
    fireEvent.click(screen.getByText("← новее"));
    expect(onPage).toHaveBeenCalledWith(1);
    expect(screen.getByText("стр. 3")).toBeTruthy();
  });
});
