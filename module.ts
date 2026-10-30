import { module } from '@prisma/composer';

import { apiService } from './packages/ilmomasiina-backend/src/prismaService';

export default module('ilmomasiina', ({ provision }) => {
    provision(apiService);
});
