// Camada de dados única (PLANO § 5.1). Alterna entre mock e supabase via VITE_DATA_SOURCE.
import * as mock from './mockProvider.js';
import * as supabase from './supabaseProvider.js';

export const fonte = import.meta.env.VITE_DATA_SOURCE || 'mock';

export const dados = fonte === 'supabase' ? supabase : mock;

