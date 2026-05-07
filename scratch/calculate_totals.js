
const fs = require('fs');

const data = JSON.parse(fs.readFileSync('scratch/appointments_data.json', 'utf8'));

const monthlyTotals = {};

data.forEach(app => {
    if (app.status === 'cancelado') return;
    if (!app.total_value) return;

    const date = new Date(app.scheduled_at);
    const month = date.toLocaleString('pt-BR', { month: 'long' });
    const year = date.getFullYear();

    if (year !== 2026) return;

    if (!monthlyTotals[month]) {
        monthlyTotals[month] = {
            total: 0,
            count: 0
        };
    }

    monthlyTotals[month].total += app.total_value;
    monthlyTotals[month].count += 1;
});

console.log(JSON.stringify(monthlyTotals, null, 2));
