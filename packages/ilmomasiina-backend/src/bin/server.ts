import debug from "debug";
import { pathToFileURL } from "node:url";
import { exit } from "process";

import initApp from "../app";
import config from "../config";
import { apiService } from "../prismaService";

const debugLog = debug("app:bin:server");

export function resolveListenPort(service: { port?: () => number } | undefined = apiService) {
  const parsedEnvPort = Number.parseInt(process.env.PORT ?? "", 10);
  if (Number.isFinite(parsedEnvPort) && parsedEnvPort > 0) {
    return parsedEnvPort;
  }

  if (service && typeof service.port === "function") {
    try {
      const port = service.port();
      if (Number.isFinite(port) && port > 0) {
        return port;
      }
    } catch {
      // Fall back to the legacy env-based flow when running outside Prisma Compute.
    }
  }

  return config.port;
}

const isDirectExecution =
  typeof process.argv[1] === "string" && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isDirectExecution) {
  initApp()
    .then(async (fastify) => {
      const { host } = config;
      const port = resolveListenPort();

      const addr = await fastify.listen({ host, port });

      await fastify.ready();

      const url = config.nodeEnv === "development" ? `http://${addr}` : config.baseUrl;
      debugLog(`Server is now running at ${url}.`);
    })
    .catch((err) => {
      console.error("Failed to initialize app", err);
      exit(1);
    });
}
