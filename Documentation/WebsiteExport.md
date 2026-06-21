# Website Export

The Denrim website lives at `../Denrim-Web`.

DenrimRendererKit documentation should be authored here first, then mirrored or transformed for the website when the publishing workflow exists.

Recommended flow:

* Keep API reference comments in Swift source.
* Keep conceptual guides in `Documentation/`.
* Generate DocC output for API reference pages.
* Copy or transform selected Markdown guides into `../Denrim-Web`.
* Treat this package as the source of truth when website content and package docs diverge.

