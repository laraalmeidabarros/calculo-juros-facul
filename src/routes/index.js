import { Router } from 'express';

import healthRoutes from './health.js';
import jurosRoutes from './juros.js';
import modalidadesRoutes from './modalidades.js';
import operacoesRoutes from './operacoes.js';

const router = Router();

// Registro central das rotas: para adicionar uma nova,
// crie o arquivo em ./routes e faça o router.use aqui.
router.use('/health', healthRoutes);
router.use('/juros', jurosRoutes);
router.use('/modalidades', modalidadesRoutes);
router.use('/operacoes', operacoesRoutes);

export default router;
