const https = require('https');

const slugs = ['edmeiapaiva', 'test-loja-markaai'];

slugs.forEach(slug => {
    https.get(`https://wismart-118c3.web.app/${slug}?t=${Date.now()}`, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
            const titleMatch = data.match(/<title>(.*?)<\/title>/);
            const title = titleMatch ? titleMatch[1] : 'No title found';
            console.log(`Slug: ${slug} | Status: ${res.statusCode} | Title: ${title}`);
        });
    }).on('error', err => console.log('Error:', err.message));
});
