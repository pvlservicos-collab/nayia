#!/bin/bash

# Extract HTML download URLs from JSON files
PIPELINE_URL=$(jq -r '.result.structuredContent.outputComponents[0].design.screens[0].htmlCode.downloadUrl' stitch_pipeline_fixed.json)
CHAT1_URL=$(jq -r '.result.structuredContent.outputComponents[0].design.screens[0].htmlCode.downloadUrl' stitch_chat1_fixed.json)
CHAT2_URL=$(jq -r '.result.structuredContent.outputComponents[0].design.screens[0].htmlCode.downloadUrl' stitch_chat2_fixed.json)

echo "Downloading Pipeline HTML..."
curl -L "$PIPELINE_URL" -o frontend/screens/pipeline.html --silent
echo "✓ Saved to frontend/screens/pipeline.html"

echo "Downloading Chat-1 HTML..."
curl -L "$CHAT1_URL" -o frontend/screens/chat-list.html --silent
echo "✓ Saved to frontend/screens/chat-list.html"

echo "Downloading Chat-2 HTML..."
curl -L "$CHAT2_URL" -o frontend/screens/chat-conversation.html --silent
echo "✓ Saved to frontend/screens/chat-conversation.html"

echo "Done!"
ls -lah frontend/screens/
