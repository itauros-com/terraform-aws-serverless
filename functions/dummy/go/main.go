package main

import (
	"context"
	"encoding/json"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/rs/zerolog/log"
)

func handleRequest(
	ctx context.Context,
	event json.RawMessage,
) (any, error) {
	log.Info().Interface("event", event).Msg("got event")

	return "OK", nil
}

func main() {
	lambda.Start(handleRequest)
}
