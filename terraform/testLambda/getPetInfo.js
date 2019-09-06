var AWS = require('aws-sdk');

var s3 = new AWS.S3();

exports.handler = function(event, context, callback) {
  console.log('event #####', event);
  console.log('context @@@@@', context);
  var params = {
    Bucket: "auth0-test-hucket",
    MaxKeys: 6
   };
  s3.listObjects(params,(err, data) => {
    if (err) {
      console.log(err, err.stack);} // an error occurred
    else {
      console.log(data);
    }
    const response = {
      "statusCode": '200',
      "body": JSON.stringify({
        'message': 'hello world',
        data: err || data,
        context,
        event
      }),
      "headers": {
        "Content-Type": "application/json",
      },
      "isBase64Encoded": false
    }

  // successful response
  callback(null, response);
  })
};
