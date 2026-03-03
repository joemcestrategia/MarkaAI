#!/usr/bin/env node
/**
 * corrigir-lojas-sem-cidade.js
 *
 * Script de migração: identifica lojas sem cidade/estado no Firestore,
 * tenta auto-corrigir via ViaCEP, gera CSV de pendentes.
 *
 * Uso:
 *   node corrigir-lojas-sem-cidade.js               # executa e corrige
 *   node corrigir-lojas-sem-cidade.js --dry-run     # apenas exibe o que faria
 *
 * Requer:
 *   npm install firebase-admin axios
 *   GOOGLE_APPLICATION_CREDENTIALS apontando para service account json.
 */

const admin = require('firebase-admin');
const axios = require('axios');
const fs = require('fs');
const path = require('path');

// ──────────────────────────────────────────────
// INIT
// ──────────────────────────────────────────────
const isDryRun = process.argv.includes('--dry-run');
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();

const LOG_PREFIX = isDryRun ? '[DRY-RUN]' : '[EXEC]';

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

/** Busca dados do ViaCEP para um CEP. Retorna null em caso de erro. */
async function buscarCep(cep) {
    const cepDigitos = cep.replace(/\D/g, '');
    if (cepDigitos.length !== 8) return null;
    try {
        const { data } = await axios.get(
            `https://viacep.com.br/ws/${cepDigitos}/json/`,
            { timeout: 6000 }
        );
        if (data.erro) return null;
        return {
            cidade: data.localidade || '',
            estado: data.uf || '',
            logradouro: data.logradouro || '',
            bairro: data.bairro || '',
            cep: data.cep || cep,
        };
    } catch (e) {
        console.warn(`  [ViaCEP] Erro para CEP ${cep}: ${e.message}`);
        return null;
    }
}

/** Gera string de data no formato ISO local */
function isoNow() {
    return new Date().toISOString().replace('T', ' ').split('.')[0];
}

// ──────────────────────────────────────────────
// MAIN
// ──────────────────────────────────────────────
async function main() {
    console.log(`\n┌─────────────────────────────────────────────┐`);
    console.log(`│  Migração: Lojas sem Cidade/Estado          │`);
    console.log(`│  Modo: ${isDryRun ? 'DRY-RUN (nenhuma escrita)' : 'EXECUÇÃO REAL        '} │`);
    console.log(`│  ${isoNow()}                          │`);
    console.log(`└─────────────────────────────────────────────┘\n`);

    // 1. Busca todas as lojas
    console.log('🔍 Buscando lojas no Firestore...');
    const snap = await db.collection('shops').get();
    console.log(`   → ${snap.size} lojas encontradas no total.\n`);

    const semCidade = [];
    const corrigidasAutomaticamente = [];
    const pendentes = [];

    for (const doc of snap.docs) {
        const data = doc.data();
        const id = doc.id;
        const nome = data.nome || '(sem nome)';
        const cidade = (data.cidade || '').trim();
        const estado = (data.estado || '').trim();

        // Pula lojas que já têm cidade E estado
        if (cidade && estado) continue;

        semCidade.push({ id, nome, cidade, estado, cep: data.cep || '' });
        console.log(`⚠️  Loja incompleta: [${id}] "${nome}" — cidade="${cidade}" estado="${estado}"`);

        // Tenta auto-corrigir via CEP
        const cep = (data.cep || '').replace(/\D/g, '');
        if (cep.length === 8) {
            process.stdout.write(`   → CEP detectado: ${cep}. Consultando ViaCEP... `);
            const resultCep = await buscarCep(cep);

            if (resultCep && resultCep.cidade && resultCep.estado) {
                console.log(`✅ Encontrado: ${resultCep.cidade}/${resultCep.estado}`);

                if (!isDryRun) {
                    await db.collection('shops').doc(id).update({
                        cidade: resultCep.cidade,
                        estado: resultCep.estado,
                        ...(resultCep.logradouro && !data.logradouro
                            ? { logradouro: resultCep.logradouro }
                            : {}),
                        ...(resultCep.bairro && !data.bairro ? { bairro: resultCep.bairro } : {}),
                        _migracao_cidade_automatica: true,
                        _migracao_em: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    console.log(`   ${LOG_PREFIX} ✅ Loja "${nome}" atualizada.`);
                } else {
                    console.log(`   ${LOG_PREFIX} Teria atualizado "${nome}" → ${resultCep.cidade}/${resultCep.estado}`);
                }

                corrigidasAutomaticamente.push({
                    id, nome, cidadeAtualizada: resultCep.cidade, estadoAtualizado: resultCep.estado,
                });
                continue;
            } else {
                console.log(`❌ CEP inválido ou não encontrado.`);
            }
        } else {
            console.log(`   → Sem CEP disponível para consulta.`);
        }

        // Pendente: não conseguiu auto-corrigir
        pendentes.push({
            id,
            nome,
            cidadeAtual: cidade,
            estadoAtual: estado,
            cep: data.cep || '',
            telefone: data.telefone || '',
            dono_id: data.dono_id || '',
        });
    }

    // ──────────────────────────────────────────────
    // 2. Relatório
    // ──────────────────────────────────────────────
    console.log('\n══════════════════ RELATÓRIO ══════════════════');
    console.log(`Total de lojas com endereço incompleto : ${semCidade.length}`);
    console.log(`Corrigidas automaticamente              : ${corrigidasAutomaticamente.length}`);
    console.log(`Ainda pendentes                         : ${pendentes.length}`);

    // Gerar CSV de pendentes
    if (pendentes.length > 0) {
        const csvHeader = 'id,nome,cidadeAtual,estadoAtual,cep,telefone,dono_id\n';
        const csvRows = pendentes.map(p =>
            [p.id, `"${p.nome}"`, p.cidadeAtual, p.estadoAtual, p.cep, p.telefone, p.dono_id].join(',')
        ).join('\n');

        const csvPath = path.join(__dirname, `lojas_pendentes_${Date.now()}.csv`);
        fs.writeFileSync(csvPath, csvHeader + csvRows, 'utf8');
        console.log(`\n📄 CSV salvo em: ${csvPath}`);
    }

    console.log('\n✅ Script concluído.\n');
}

main().catch(err => {
    console.error('❌ Erro no script:', err);
    process.exit(1);
});
