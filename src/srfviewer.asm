srf_request:    !byte "R",WIC64_HTTP_GET, <srf_url_size, >srf_url_size
srf_url:        !text "https://api.teletext.ch/channels/SRF1/pages/"
srf_input           !text '1','0','0'
srf_url_size = * - srf_url
