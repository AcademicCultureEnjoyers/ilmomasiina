import { module } from '@prisma/composer';
import { compute } from '@prisma/composer-prisma-cloud';
import node from '@prisma/composer/node';

// This repository still runs its API as a Fastify app, so the Composer declaration
// is intentionally minimal and names the root app "ilmomasiina" for the connected
// Prisma project. Once the backend is ported, wire the actual server here.
export default module('ilmomasiina', ({ provision }) => {
    provision(
        compute({
            name: 'api',
            deps: {},
            build: node({
                module: import.meta.url,
                entry: './packages/ilmomasiina-backend/dist/bin/server.js',
            }),
        }),
    );
});
