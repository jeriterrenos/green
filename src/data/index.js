// Camada de dados única (PLANO § 5.1). Na fase F5 entra o supabaseProvider, escolhido por VITE_DATA_SOURCE.
import * as mock from './mockProvider.js';

export const fonte = import.meta.env.VITE_DATA_SOURCE || 'mock';

if (fonte !== 'mock') {
  console.warn(`VITE_DATA_SOURCE="${fonte}" ainda não implementado (fase F5); usando a demonstração.`);
}

export const dados = mock;
