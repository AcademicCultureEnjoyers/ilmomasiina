import { compute } from "@prisma/composer-prisma-cloud";
import node from "@prisma/composer/node";

export const apiService = compute({
    name: "api",
    deps: {},
    build: node({
        module: import.meta.url,
        entry: "./bin/server.js",
    }),
});
