// Sends every visit to the one public address, https://sicatat.com.
//
// Old links (sicatat-5l5.pages.dev), per-deployment preview URLs, and
// www.sicatat.com all land on the same place. _routes.json limits this worker
// to page loads ("/"), so static assets never run it and never count against
// the Workers free request quota.
//
// 302 rather than 301: browsers cache a 301 forever, which would strand users
// if the custom domain ever lapsed.
const CANONICAL_HOST = 'sicatat.com';

// _headers is not applied to responses a worker returns, so the page itself
// carries the same security headers here.
const SECURITY_HEADERS = {
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'geolocation=(), microphone=(), payment=(), usb=()',
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname !== CANONICAL_HOST) {
      url.hostname = CANONICAL_HOST;
      url.protocol = 'https:';
      url.port = '';
      return Response.redirect(url.toString(), 302);
    }
    const response = await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);
    for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
      headers.set(name, value);
    }
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
};
