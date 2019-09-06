provider "aws" {
  version = "~> 2.0"
  region  = "ap-southeast-2"
}

# ! S3 BUCKET
resource "aws_s3_bucket" "auth0_test_bucket" {
  bucket        = "auth0-test-hucket"
  acl           = "private"
  force_destroy = true

  tags = {
    Name        = "Auth0"
    Environment = "Test"
  }
}

resource "aws_s3_bucket_public_access_block" "auth0_test_bucket" {
  bucket = "${aws_s3_bucket.auth0_test_bucket.id}"

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

# ! LAMBDAS COMMON
data "archive_file" "node_modules" {
  type        = "zip"
  source_dir  = "./testLambda/node_modules"
  output_path = "node_modules.zip"
}

resource "aws_lambda_layer_version" "lambda_node_modules" {
  filename   = "node_modules.zip"
  layer_name = "node_modules"

  compatible_runtimes = ["nodejs10.x"]

  depends_on = ["data.archive_file.node_modules"]
}

# ! COMMON ASSUME POLICY FOR LAMBDAs
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  version = "2012-10-17"
  # ASSUME ROLE
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    effect = "Allow"

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ! LAMBDA - GetPetInfo
resource "aws_iam_role" "lambda_s3_get" {
  name               = "LambdaExecS3GetRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3_get" {
  role       = aws_iam_role.lambda_s3_get.name
  policy_arn = aws_iam_policy.lambda_s3_get.arn
}

resource "aws_iam_policy" "lambda_s3_get" {
  name   = "LambdaExecS3GetPolicy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.lambda_s3_get.json}"
}

data "aws_iam_policy_document" "lambda_s3_get" {
  version = "2012-10-17"

  statement {
    sid = "AccessCloudwatchLogs"
    actions = ["logs:*"]
    effect = "Allow"
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "PetsS3Read"
    effect = "Allow"
    actions = [
      "s3:List*",
      "s3:GetObject"
    ]
    resources = ["${aws_s3_bucket.auth0_test_bucket.arn}"]
  }
}

data "archive_file" "get_pet_info" {
  type = "zip"
  source_file = "./testLambda/getPetInfo.js"
  output_path = "getPetInfo.zip"
}

resource "aws_lambda_function" "auth0_test_get" {
  filename = "${data.archive_file.get_pet_info.output_path}"
  function_name = "GetPetInfo"
  role = aws_iam_role.lambda_s3_get.arn
  handler = "getPetInfo.handler"
  runtime = "nodejs10.x"
  source_code_hash = "${filebase64sha256("${data.archive_file.get_pet_info.output_path}")}"
  publish = true
}

# ! LAMBDA - UpdatePetInfo
resource "aws_iam_role" "lambda_s3_update" {
  name               = "LambdaExecS3UpdateRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3_update" {
  role       = aws_iam_role.lambda_s3_update.name
  policy_arn = aws_iam_policy.lambda_s3_update.arn
}

resource "aws_iam_policy" "lambda_s3_update" {
  name   = "LambdaExecS3UpdatePolicy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.lambda_s3_update.json}"
}

data "aws_iam_policy_document" "lambda_s3_update" {
  version = "2012-10-17"

  statement {
    sid = "AccessCloudwatchLogs"
    actions = ["logs:*"]
    effect = "Allow"
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "PetsS3Write"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.auth0_test_bucket.arn}/*"]
  }
}

data "archive_file" "update_pet_info" {
  type = "zip"
  source_file = "./testLambda/updatePetInfo.js"
  output_path = "updatePetInfo.zip"
}

resource "aws_lambda_function" "auth0_test_post" {
  filename = "${data.archive_file.update_pet_info.output_path}"
  function_name = "UpdatePetInfo"
  role = aws_iam_role.lambda_s3_update.arn
  handler = "updatePetInfo.handler"
  runtime = "nodejs10.x"
  source_code_hash = "${filebase64sha256("${data.archive_file.update_pet_info.output_path}")}"
  publish = true
}

# !___ API GATEWAY COMMON ___ #
resource "aws_api_gateway_rest_api" "auth0_test" {
  name        = "Auth0Test"
  description = "A POST and GET method for the Auth0 test"
}

resource "aws_api_gateway_resource" "auth0_test_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.auth0_test.id}"
  parent_id   = "${aws_api_gateway_rest_api.auth0_test.root_resource_id}"
  path_part   = "auth0-test"
}

resource "aws_api_gateway_deployment" "example_deployment_dev" {
  depends_on = [
    "aws_api_gateway_method.auth0_test_get_method",
    "aws_api_gateway_method.auth0_test_post_method",
    "aws_api_gateway_method.auth0_test_options_method",
    "aws_api_gateway_integration.auth0_test_get_method",
    "aws_api_gateway_integration.auth0_test_post_method",
    "aws_api_gateway_integration.auth0_test_options_method"
  ]
  rest_api_id = "${aws_api_gateway_rest_api.auth0_test.id}"
  stage_name  = "dev"
}

# Remove this if I don't want to use user pools auth
# resource "aws_api_gateway_authorizer" "auth0_test" {
#   name          = "CognitoUserPoolAuthorizer"
#   type          = "COGNITO_USER_POOLS"
#   rest_api_id   = "${aws_api_gateway_rest_api.auth0_test.id}"
#   provider_arns = ["${module.cognito.user_pool_arn}"]
# }

# ! POST METHOD #
resource "aws_api_gateway_method" "auth0_test_post_method" {
  rest_api_id   = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id   = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method   = "POST"
  # authorization = "AWS_IAM" remove the next 3 keys
  authorization = "NONE"
  # authorizer_id = "${aws_api_gateway_authorizer.auth0_test.id}"
  # authorization_scopes = ["email"]

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "auth0_test_post_method" {
  rest_api_id             = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id             = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method             = "${aws_api_gateway_method.auth0_test_post_method.http_method}"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${var.account_id}:function:${aws_lambda_function.auth0_test_post.function_name}/invocations"
  integration_http_method = "POST"
}

resource "aws_lambda_permission" "apigw_lambda_post" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.auth0_test_post.function_name}"
  principal     = "apigateway.amazonaws.com"

  # Docs for this: https://www.terraform.io/docs/providers/aws/r/lambda_permission.html#specify-lambda-permissions-for-api-gateway-rest-api
  # Although this doesn't seem to be correct cus I'm getting an error in the console about how the API Gateway resource doesn't have an ANY method associated with it.
  source_arn = "${aws_api_gateway_rest_api.auth0_test.execution_arn}/*/*"
}

resource "aws_api_gateway_authorizer" "auth0_test_post" {
  name                   = "auth0-test"
  rest_api_id            = "${aws_api_gateway_rest_api.auth0_test.id}"
  authorizer_uri         = "${aws_lambda_function.auth0_test_post.invoke_arn}"
  authorizer_credentials = "${aws_iam_role.saml_provider.arn}"
}

# ! GET METHOD #
resource "aws_api_gateway_method" "auth0_test_get_method" {
  rest_api_id   = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id   = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method   = "GET"
  # authorization = "AWS_IAM" remove the next 3 keys
  authorization = "NONE"
  # authorizer_id = "${aws_api_gateway_authorizer.auth0_test.id}"
  # authorization_scopes = ["email"]

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "auth0_test_get_method" {
  rest_api_id             = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id             = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method             = "${aws_api_gateway_method.auth0_test_get_method.http_method}"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${var.account_id}:function:${aws_lambda_function.auth0_test_get.function_name}/invocations"
  # Lambda functions can only be invoke wit hthe POST method - https://www.terraform.io/docs/providers/aws/r/api_gateway_integration.html#integration_http_method
  integration_http_method = "POST"
}

resource "aws_lambda_permission" "apigw_lambda_get" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.auth0_test_get.function_name}"
  principal     = "apigateway.amazonaws.com"

  # Docs for this: https://www.terraform.io/docs/providers/aws/r/lambda_permission.html#specify-lambda-permissions-for-api-gateway-rest-api
  # Although this doesn't seem to be correct cus I'm getting an error in the console about how the API Gateway resource doesn't have an ANY method associated with it.
  source_arn = "${aws_api_gateway_rest_api.auth0_test.execution_arn}/*/*"
}

# ! OPTIONS METHOD #
resource "aws_api_gateway_method" "auth0_test_options_method" {
  rest_api_id   = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id   = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method   = "OPTIONS"
  # authorization = "AWS_IAM" remove the next 3 keys
  authorization = "NONE"
  # authorizer_id = "${aws_api_gateway_authorizer.auth0_test.id}"
  # authorization_scopes = ["email"]

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "auth0_test_options_method" {
  rest_api_id             = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id             = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method             = "${aws_api_gateway_method.auth0_test_options_method.http_method}"
  type                    = "MOCK"
}

resource "aws_api_gateway_method_response" "auth0_test_options" {
  rest_api_id = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method = "${aws_api_gateway_method.auth0_test_options_method.http_method}"
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Origin" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = "${aws_api_gateway_rest_api.auth0_test.id}"
  resource_id = "${aws_api_gateway_resource.auth0_test_resource.id}"
  http_method = "${aws_api_gateway_method.auth0_test_options_method.http_method}"
  status_code = "${aws_api_gateway_method_response.auth0_test_options.status_code}"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,GET,OPTIONS'"
  }
}

# ! SAML PROVIDER
resource "aws_iam_saml_provider" "auth0_test" {
  name                   = "AuthTestProvider"
  saml_metadata_document = "${file("./auth0CredDocs/saml-metadata.xml")}"
}

resource "aws_iam_role" "saml_provider" {
  name               = "SamlProviderRole"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "auth0TestAssumeSaml",
      "Effect": "Allow",
      "Principal": {
        "Federated": "${aws_iam_saml_provider.auth0_test.arn}"
      },
      "Action": "sts:AssumeRoleWithSAML",
      "Condition": {
        "StringEquals": {
          "SAML:iss": "${var.auth0_domain}"
        }
      }
    },
    {
      "Sid": "gateway",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}
# ! ERROR - Error creating IAM Role SamlProviderRole: MalformedPolicyDocument: Invalid principal in policy: "AWS":"arn:aws:iam::829131444792:saml-provider/AuthTestProvider"
# * Have to use the EOF method that I've used before when federating
# data "aws_iam_policy_document" "saml_provider_assume_policy" {
#   version = "2012-10-17"
#   # ASSUME ROLE
#   statement {
#     sid = "auth0TestAssumeSaml"
#     actions = [
#       "sts:AssumeRoleWithSAML",
#     ]

#     effect = "Allow"

#     principals {
#       type = "AWS"
#       identifiers = ["${aws_iam_saml_provider.auth0_test.arn}"]
#     }

#     condition {
#       test = "StringEquals"
#       variable = "SAML:iss"
#       values = [
#         "${var.auth0_domain}"
#       ]
#     }
#   }

#   statement {
#     sid = "auth0TestAssumeGateway"

#     effect = "Allow"

#     principals {
#       type = "AWS"
#       identifiers = ["${aws_api_gateway_rest_api.auth0_test.execution_arn}/*"]
#     }

#     actions = [
#       "sts:AssumeRole"
#     ]
#   }
# }

resource "aws_iam_role_policy_attachment" "saml_provider" {
  role       = aws_iam_role.saml_provider.name
  policy_arn = aws_iam_policy.saml_provider.arn
}

resource "aws_iam_policy" "saml_provider" {
  name   = "Auth0ExecuteApi"
  policy = "${data.aws_iam_policy_document.saml_provider.json}"
}

data "aws_iam_policy_document" "saml_provider" {
  version = "2012-10-17"

  statement {
    sid = "Auth0ExecuteApi"
    effect = "Allow"
    actions = [
      "execute-api:*"
    ]
    resources = ["${aws_api_gateway_rest_api.auth0_test.execution_arn}/*"]
  }
}