import { compute } from "@prisma/composer-prisma-cloud";
import node from "@prisma/composer/node";

const apiService = compute({
    name: "api",
    deps: {},
    build: node({
        module: import.meta.url,
        entry: "./bin/server.js",
    }),
});

// Prisma Cloud bootstraps the built service by importing the default export and calling
// `main.run(address, boot)`. Keep this default export available even for the named local use
// in the legacy direct-execution code path.
export default apiService;
export { apiService };
