const axios = require('axios');

// Cache em memória para evitar múltiplas chamadas no mesmo ciclo de execução
const cacheFeriados = {};

/**
 * Busca feriados nacionais via BrasilAPI para um determinado ano.
 * Retorna: [{ date: "2026-04-21", name: "Tiradentes", type: "national" }, ...]
 */
async function fetchFeriadosNacionais(ano) {
  if (cacheFeriados[ano]) {
    return cacheFeriados[ano];
  }

  try {
    const response = await axios.get(`https://brasilapi.com.br/api/feriados/v1/${ano}`);
    
    // Mapeia para o formato unificado esperado pelo sistema
    const feriados = (response.data || []).map(f => ({
      date: f.date,
      name: f.name,
      type: 'national'
    }));

    cacheFeriados[ano] = feriados;
    return feriados;
  } catch (error) {
    console.error(`[brasilapi] Erro ao buscar feriados para ${ano}:`, error.message);
    return [];
  }
}

module.exports = { fetchFeriadosNacionais };
