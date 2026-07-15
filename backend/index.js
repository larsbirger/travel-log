const path = require('path');
const fastify = require('fastify')({ logger: true });

fastify.register(require('@fastify/autoload'), {
    dir: path.join(__dirname, 'src', 'routes')
});

fastify.listen({ port:3000, host: '0.0.0.0' });