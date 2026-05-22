const jwt = require('jsonwebtoken');
const secret = '7uKRCoWcl8BPSYjteqpdJwHrE4FhmV6U902OI1NgbMafGL5nDTsxkQAy3ZzivX';
const token = jwt.sign({ sub: '12345678-1234-1234-1234-123456789abc', type: 'api_token' }, secret);
console.log(token);
