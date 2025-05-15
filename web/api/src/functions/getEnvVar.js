const { app } = require('@azure/functions');

app.http('getEnvVar', {
    methods: ['GET', 'POST'],
    authLevel: 'anonymous',
    handler: async (request, context) => {
        context.log(`Http function processed request for url "${request.url}"`);


        const myEnvVar = process.env.UPDATE_TIME; // Replace with your variable name
        context.res = {
            body: { value: myEnvVar },
            headers: {
                'Content-Type': 'application/json'
            }
        };

    }
});
