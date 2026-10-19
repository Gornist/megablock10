import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { QrPanel } from "./common";

const result = { qr: "MB10:PROV:v1:i1", qrImage: "data:image/png;base64,AAA" };

describe("QrPanel: код для ввода без камеры", () => {
  it("показывает короткий код рядом с QR, если он есть", () => {
    render(<QrPanel result={result} caption="Alice" code="ABC-DEF" />);
    expect(screen.getByText("ABC-DEF")).toBeTruthy();
    expect(screen.getByText(/код без камеры/)).toBeTruthy();
  });

  it("без кода (шард, RAM, контейнер, применённая выдача) строки про код нет", () => {
    render(<QrPanel result={result} caption="Alice" code={null} />);
    expect(screen.queryByText(/код без камеры/)).toBeNull();
  });
});
