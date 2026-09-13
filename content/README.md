# Content packs

Empty until deliverable 3, which defines the schema and the loader.

The layout will be `content/<language>/`, with `content/en/` shipping first and
`content/ru/` (or any other language) droppable alongside it **without a code change**.
Each item carries an id, text, an audio filename, an optional illustration, an optional
accepted-answer list, and tags.

Audio will be recorded by a voice actor. During development, `AVSpeechSynthesizer`
stands in behind a feature flag.
