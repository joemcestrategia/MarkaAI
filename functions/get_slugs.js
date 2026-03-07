const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function getSlugs() {
    try {
        const snap = await db.collection('shops').select('slug', 'nome').get();
        const slugs = [];
        snap.forEach(doc => {
            const data = doc.data();
            if (data.slug) slugs.push(data.slug);
        });
        console.log('SLUGS:', slugs.join(', '));
        process.exit(0);
    } catch (err) {
        console.error('Error:', err.message);
        process.exit(1);
    }
}

getSlugs();
