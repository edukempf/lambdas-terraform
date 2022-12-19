exports.handler = function (event, context, callback) {
    console.log('oi')
	callback(null, {
        statusCode: 200,
        body: JSON.stringify({"test": "hello world"})
    });
};