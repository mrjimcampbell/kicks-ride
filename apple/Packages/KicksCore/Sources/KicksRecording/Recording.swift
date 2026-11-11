import Foundation
import KicksCore

/// Strava upload goes through the existing Cloudflare Worker relay, which holds the client
/// secret. The app never sees or stores the secret.
public enum StravaRelay {
    public static let baseURL = URL(string: "https://kicks-ride-strava.jim-campbell.workers.dev")!
}

// TODO(milestone 1): TCX writer (a lap per workout block), port from index.html;
// OAuth via ASWebAuthenticationSession → relay /token, /refresh; upload via /upload.
