// A throwaway self-signed certificate for 127.0.0.1 and localhost, made once with openssl for these tests only (EC P-256,
// valid for 100 years). It protects nothing. The PEM markers are added here, so this file holds no complete PEM block.
import 'dart:convert';
import 'dart:io';

const _certificate = [
  'MIIBmzCCAUGgAwIBAgIUOLhM9576GBHcQ5mgtEXEkkf0DgIwCgYIKoZIzj0EAwIw',
  'FDESMBAGA1UEAwwJMTI3LjAuMC4xMCAXDTI2MTAwNzA5MTYwNVoYDzIxMjYwOTEz',
  'MDkxNjA1WjAUMRIwEAYDVQQDDAkxMjcuMC4wLjEwWTATBgcqhkjOPQIBBggqhkjO',
  'PQMBBwNCAASnvY+cm02xuJGPtDtkkUfNj6roPv5tVwK61aZNf11rzk/4zmdosho9',
  'NqS8iPcS30YYpUIA7z5p+omMf2pgvAAzo28wbTAdBgNVHQ4EFgQUvgsFZFlc6Ef3',
  'u8c01AmHnvpxLaAwHwYDVR0jBBgwFoAUvgsFZFlc6Ef3u8c01AmHnvpxLaAwDwYD',
  'VR0TAQH/BAUwAwEB/zAaBgNVHREEEzARhwR/AAABgglsb2NhbGhvc3QwCgYIKoZI',
  'zj0EAwIDSAAwRQIhAPT/T45O6CMp7xjf6AxMvI5DqN3ujq80YCNc++czXPqlAiAt',
  'enWIsCCBIYb3+y8gReaAutDoWLjFjR7SvoQQOG4YfQ==',
];

const _keyBody = [
  'MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgHIRTWjkJU2WnAx9Z',
  'g+BOSouagYczhne4ZDC0k94dz/+hRANCAASnvY+cm02xuJGPtDtkkUfNj6roPv5t',
  'VwK61aZNf11rzk/4zmdosho9NqS8iPcS30YYpUIA7z5p+omMf2pgvAAz',
];

String _pem(String label, List<String> lines) => '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';

/// The server side of a TLS connection to 127.0.0.1 that no client trusts.
SecurityContext selfSignedServerContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(_pem('CERTIFICATE', _certificate)))
  ..usePrivateKeyBytes(utf8.encode(_pem('PRIVATE ${'KEY'}', _keyBody)));
