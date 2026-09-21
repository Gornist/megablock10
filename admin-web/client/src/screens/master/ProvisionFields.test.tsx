import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ProvisionFields, type ProvisionValues } from "./ProvisionFields";

const values: ProvisionValues = { callsign: "", faction: "", balance: "0", ram: "0" };

describe("ProvisionFields", () => {
  it("в баланс попадают только цифры", () => {
    const onChange = vi.fn();
    render(<ProvisionFields values={values} onChange={onChange} />);
    fireEvent.change(screen.getByPlaceholderText("0"), { target: { value: "12a-3" } });
    expect(onChange).toHaveBeenCalledWith({ ...values, balance: "123" });
  });

  it("RAM: «по умолчанию» и 6…13; текущий нестандартный RAM игрока добавляется в список", () => {
    render(<ProvisionFields values={values} onChange={() => {}} extraRam={5} />);
    const options = [...screen.getAllByRole("option")].map((o) => o.textContent);
    expect(options).toContain("по умолчанию");
    expect(options).toContain("13");
    expect(options).toContain("5");
  });

  it("подсказки фракций и правка позывного", () => {
    const onChange = vi.fn();
    const { container } = render(<ProvisionFields values={values} onChange={onChange} factions={["Neon", "Rats"]} />);
    expect(container.querySelectorAll("datalist option").length).toBe(2);
    fireEvent.change(screen.getByPlaceholderText("Alice"), { target: { value: "Zed" } });
    expect(onChange).toHaveBeenCalledWith({ ...values, callsign: "Zed" });
  });
});
