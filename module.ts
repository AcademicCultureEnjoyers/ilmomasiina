import { module } from '@prisma/composer';

import apiService from './packages/ilmomasiina-backend/dist/prismaService.js';

export default module('ilmomasiina', ({ provision }) => {
    provision(apiService);
});
