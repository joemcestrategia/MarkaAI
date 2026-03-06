const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Inicialize com as credenciais padrões do ambiente (GCP/Firebase)
// export GOOGLE_APPLICATION_CREDENTIALS="/caminho/para/sua/chave-de-servico.json"
if (!admin.apps.length) {
    admin.initializeApp();
}

const db = admin.firestore();

async function runAudit() {
    console.log("Iniciando auditoria de contas duplicadas...");
    const usersSnapshot = await db.collection('users').get();

    const byEmail = {};
    const byPhone = {};
    const byNameAndBirth = {};

    usersSnapshot.forEach(doc => {
        const data = doc.data();
        const id = doc.id;
        const entry = { id, nome: data.nome, email: data.email, telefone: data.telefone, aniversario: data.aniversario, tipo: data.tipo };

        // Agrupar por Email
        if (data.email) {
            const email = data.email.toLowerCase().trim();
            if (!byEmail[email]) byEmail[email] = [];
            byEmail[email].push(entry);
        }

        // Agrupar por Telefone
        if (data.telefone) {
            const phone = data.telefone;
            if (!byPhone[phone]) byPhone[phone] = [];
            byPhone[phone].push(entry);
        }

        // Agrupar por Homônimos (Nome Normalizado + Data de Nascimento)
        if (data.nome_normalizado && data.aniversario) {
            const key = `${data.nome_normalizado}::${data.aniversario}`;
            if (!byNameAndBirth[key]) byNameAndBirth[key] = [];
            byNameAndBirth[key].push(entry);
        }
    });

    const report = {
        total_usuarios_analisados: usersSnapshot.size,
        data_auditoria: new Date().toISOString(),
        duplicados_por_email: {},
        duplicados_por_telefone: {},
        possiveis_homonimos: {}
    };

    // Filtrar apenas os que tem > 1 conta no mesmo grupo
    for (const [email, users] of Object.entries(byEmail)) {
        if (users.length > 1) report.duplicados_por_email[email] = users;
    }

    for (const [phone, users] of Object.entries(byPhone)) {
        if (users.length > 1) report.duplicados_por_telefone[phone] = users;
    }

    for (const [key, users] of Object.entries(byNameAndBirth)) {
        if (users.length > 1) {
            const [nome, niver] = key.split('::');
            report.possiveis_homonimos[`Nome: ${nome} | Nasc: ${niver}`] = users;
        }
    }

    const reportPath = path.join(__dirname, 'relatorio_duplicatas.json');
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log(`Auditoria concluída com sucesso!`);
    console.log(`Relatório salvo em: ${reportPath}`);
    console.log(`- Emails duplicados encontrados: ${Object.keys(report.duplicados_por_email).length}`);
    console.log(`- Telefones duplicados encontrados: ${Object.keys(report.duplicados_por_telefone).length}`);
    console.log(`- Homônimos encontrados: ${Object.keys(report.possiveis_homonimos).length}`);
}

runAudit().catch(console.error);
