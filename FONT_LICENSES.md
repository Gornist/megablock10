# Bundled fonts

`app/src/main/res/font/{jura,jetbrains_mono,ibm_plex_sans}.ttf` are the variable-font
sources from Google's open-source font repository, licensed under the SIL Open Font
License, Version 1.1 (https://openfontlicense.org):

- Jura — https://github.com/google/fonts/tree/main/ofl/jura
- JetBrains Mono — https://github.com/google/fonts/tree/main/ofl/jetbrainsmono
- IBM Plex Sans — https://github.com/google/fonts/tree/main/ofl/ibmplexsans

Bundled as regular resources (not via Compose's Downloadable Fonts / GoogleFont
provider) because the venue has no internet access — see the project style guide.
