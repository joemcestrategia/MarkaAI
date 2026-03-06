const jsonwebtoken = require('jsonwebtoken');

describe('Geração de Secret para o Apple Web Login', () => {
    it('deve assinar um JWT (client_secret) sem falhas', () => {
        const appleTeamId = 'TEST_TEAM';
        const appleClientId = 'br.com.teste.web';
        const appleKeyId = 'TEST_KEY';

        // Simulação de p8 (Elliptic Curve Key genérica para que o jwt assine apenas local)
        // O NodeJS Crypto precisa de uma chave válida para falhar só de leitura. 
        // Como MOCK, vamos testar apenas a formação se passarmos um segredo 'shhhh' (HS256 mock apenas de prova unitária).
        const secretBase = 'my-secret-mock';

        const clientSecret = jsonwebtoken.sign({}, secretBase, {
            algorithm: 'HS256', // Apenas mock. Produção usa ES256 + P8 Private Key string válida
            audience: 'https://appleid.apple.com',
            issuer: appleTeamId,
            subject: appleClientId,
            expiresIn: '1h'
        });

        const decoded = jsonwebtoken.decode(clientSecret, { complete: true });

        expect(clientSecret).toBeDefined();
        expect(decoded.payload.iss).toBe(appleTeamId);
        expect(decoded.payload.aud).toBe('https://appleid.apple.com');
        expect(decoded.payload.sub).toBe(appleClientId);
    });

    it('deve extrair SUB e EMAIL corretamente do id_token fake', () => {
        const idTokenMock = jsonwebtoken.sign({
            sub: '12345.apple.user',
            email: 'test@privaterelay.appleid.com'
        }, 'mock-key');

        const decoded = jsonwebtoken.decode(idTokenMock) || {};
        const appleSub = decoded.sub;
        const appleEmail = decoded.email;

        expect(appleSub).toBe('12345.apple.user');
        expect(appleEmail).toBe('test@privaterelay.appleid.com');
    });
});
