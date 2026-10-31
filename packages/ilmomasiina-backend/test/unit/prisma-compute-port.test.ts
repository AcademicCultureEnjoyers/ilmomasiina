import { describe, expect, it } from "vitest";

import { resolveListenPort } from "../../src/bin/server";
import prismaServiceModule from "../../src/prismaService";

describe("resolveListenPort", () => {
  it("uses the Composer runtime port when the process env does not override it", () => {
    const previous = process.env.PORT;
    delete process.env.PORT;

    try {
      const resolved = resolveListenPort({ port: () => 4242 });
      expect(resolved).toBe(4242);
    } finally {
      if (previous === undefined) {
        delete process.env.PORT;
      } else {
        process.env.PORT = previous;
      }
    }
  });

  it("falls back to the process port for legacy direct execution", () => {
    const previous = process.env.PORT;
    process.env.PORT = "3100";

    try {
      const resolved = resolveListenPort();
      expect(resolved).toBe(3100);
    } finally {
      if (previous === undefined) {
        delete process.env.PORT;
      } else {
        process.env.PORT = previous;
      }
    }
  });

  it("exports the default Composer node entry expected by the Cloud bootstrap", () => {
    expect(prismaServiceModule).toBeDefined();
    expect(prismaServiceModule).toHaveProperty("run");
    expect(typeof prismaServiceModule.run).toBe("function");
  });

  it("stages runtime dependencies for the deployed app entry so packages like debug are present", () => {
    expect(prismaServiceModule.build).toBeDefined();
    expect(prismaServiceModule.build.dependencies).toBe("external");
  });
});
