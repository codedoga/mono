import { describe, expect, it } from "bun:test";
import { hello } from "./index";

describe("{{LIB_NAME}}", () => {
  it("should return greeting", () => {
    expect(hello()).toBe("Hello from {{LIB_NAME}}!");
  });
});
