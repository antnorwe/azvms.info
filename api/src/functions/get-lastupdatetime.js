const { app } = require('@azure/functions');

app.http('get-lastupdatetime', {
    methods: ['GET'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        context.log(`Http function processed request for url "${request.url}"`);

        const name = process.env.LAST_UPDATE_TIME || '2025-07-17 07:00:00';

        return { body: {
            lastUpdateTime: name}
         };
    }
});
