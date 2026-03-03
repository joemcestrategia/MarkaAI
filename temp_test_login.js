
const https = require('https');

const data = JSON.stringify({
    email: 'test_agent_login@markaai.com.br',
    password: 'TestPassword123!',
    returnSecureToken: true
});

const options = {
    hostname: 'identitytoolkit.googleapis.com',
    port: 443,
    path: '/v1/accounts:signInWithPassword?key=AIzaSyBpneZQEJ6BlKbtJaBfwlKAXTxGCV-XCFs',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
    },
    timeout: 10000
};

console.log('Verifying login for test_agent_login@markaai.com.br...');

const req = https.request(options, (res) => {
    console.log(`Status Code: ${res.statusCode}`);
    let responseData = '';

    res.on('data', (d) => {
        responseData += d;
    });

    res.on('end', () => {
        const json = JSON.parse(responseData);
        if (res.statusCode === 200) {
            console.log('✅ LOGIN SUCCESSFUL!');
            console.log('User ID:', json.localId);
        } else {
            console.log('❌ LOGIN FAILED:', json.error.message);
        }
    });
});

req.on('error', (error) => {
    console.error('Error:', error);
});

req.on('timeout', () => {
    console.error('Request timed out');
    req.destroy();
});

req.write(data);
req.end();
