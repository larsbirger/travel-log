module.exports = async function (fastify, opts) {
    // Maps directly to: GET /health
    fastify.get('/api/health', async (request, reply) => {
      return { 
        status: 'OK', 
        uptime: process.uptime(),
        timestamp: new Date().toISOString()
      };
    });
  };