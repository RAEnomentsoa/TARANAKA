import csv
import io

from rest_framework.negotiation import BaseContentNegotiation
from rest_framework.renderers import BaseRenderer


class CSVRenderer(BaseRenderer):
    """Rows (a list of lists) as CSV. An error (a dict) becomes key,value lines."""

    media_type = "text/csv"
    format = "csv"
    charset = "utf-8"

    def render(self, data, accepted_media_type=None, renderer_context=None):
        sortie = io.StringIO()
        ecrivain = csv.writer(sortie)
        if isinstance(data, dict):
            for cle, valeur in data.items():
                ecrivain.writerow([cle, valeur])
        else:
            ecrivain.writerows(data or [])
        return sortie.getvalue().encode(self.charset)


class ToujoursCsv(BaseContentNegotiation):
    """The export is CSV whatever the Accept header: `text/csv`, `*/*` and,
    as before, `application/json` all get the file (no 406)."""

    def select_parser(self, request, parsers):
        return parsers[0] if parsers else None

    def select_renderer(self, request, renderers, format_suffix=None):
        return renderers[0], renderers[0].media_type
