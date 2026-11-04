import io
import zlib

from django.conf import settings
from django.http import JsonResponse


class DecompressionGzip:
    """Accept gzip-compressed request bodies (spec §9: "petits lots compressés").

    The decompressed size is capped, so a small "zip bomb" can't fill memory.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.headers.get("Content-Encoding", "").lower() == "gzip":
            limite = settings.DATA_UPLOAD_MAX_MEMORY_SIZE
            try:
                decompresseur = zlib.decompressobj(16 + zlib.MAX_WBITS)
                corps = decompresseur.decompress(request.body, limite + 1)
            except zlib.error:
                return JsonResponse(
                    {"detail": "Corps gzip illisible.", "code": "gzip_invalide"},
                    status=400,
                )
            if len(corps) > limite or decompresseur.unconsumed_tail:
                return JsonResponse(
                    {"detail": "Corps trop volumineux.", "code": "trop_volumineux"},
                    status=413,
                )
            request._body = corps
            request._stream = io.BytesIO(corps)
            request.META["CONTENT_LENGTH"] = str(len(corps))
            del request.META["HTTP_CONTENT_ENCODING"]
        return self.get_response(request)
