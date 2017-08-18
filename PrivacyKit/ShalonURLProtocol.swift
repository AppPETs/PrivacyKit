import Foundation

class ShalonURLProtocol : URLProtocol {
    var loadingShouldStop: Bool = false

    override class func canInit(with request: URLRequest) -> Bool {
        if let url = request.url {
            let url_scheme = url.scheme
            if     url_scheme == "httpss"
                || url_scheme == "httpsss"
                || url_scheme == "httpssss" {
                print("Shalon will handle request")
                return true
            } else {
                print("Shalon will _not_ handle request")
                return false
            }
        }

        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    //    override class func canInit(with task: URLSessionTask) -> Bool {
    //        print("Not yet implemented")
    //        return false
    //    }
    //
    enum ShalonErrors : Error {
        case NotImplemented
        case UnknownHTTPMethod
        case NoContents
    }

    override func startLoading() {
        if let url_scheme = request.url?.scheme {
            if url_scheme == "httpsss" || url_scheme == "httpssss" {
                print("Loading failed, not yet implemented.")
                client!.urlProtocol(self, didFailWithError: ShalonErrors.NotImplemented)
                client!.urlProtocolDidFinishLoading(self)
                return
            }
        }

        let urlString = request.url!.absoluteString

        // Remove leading httpssss and simply replace with a single https
        var url : URL? = nil
        if urlString.hasPrefix("httpss://") {
            let index = urlString.index(urlString.startIndex, offsetBy: "httpss://".characters.count)
            url = URL(string: "https://" + urlString.substring(from: index))
            print(url!)
        } else if urlString.hasPrefix("httpsss://") {
            let index = urlString.index(urlString.startIndex, offsetBy: "httpsss://".characters.count)
            url = URL(string: "https://" + urlString.substring(from: index))
            print(url!)
        } else /* if urlString.hasPrefix("httpssss://") */ {
            let index = urlString.index(urlString.startIndex, offsetBy: "httpssss://".characters.count)
            url = URL(string: "https://" + urlString.substring(from: index))
            print(url!)
        }

        let target = Target(withHostname: url!.host!, andPort: 443)!
        let shalon = Shalon(withTarget: target)

        shalon.addLayer(Target(withHostname: "shalon1.jondonym.net", andPort: 443)!)

        let optionalMethod = Method(rawValue: request.httpMethod!.uppercased())
        guard optionalMethod != nil else {
            client!.urlProtocol(self, didFailWithError: ShalonErrors.UnknownHTTPMethod)
            return
        }

        shalon.issue(request: Request(withMethod: optionalMethod!, andUrl: url!)!) {
            receivedOptionalResponse, receivedOptionalError in

            print("Handling response from URLProtocol handler")
            guard !self.loadingShouldStop else {
                return
            }

            // Handle any errors
            if let error = receivedOptionalError {
                self.client!.urlProtocol(self, didFailWithError: error)
                return
            }

            // Handle a correct response
            if let response = receivedOptionalResponse {
                let url_response = URLResponse(url: self.request.url!, mimeType: nil, expectedContentLength: response.body.count, textEncodingName: nil)
                self.client!.urlProtocol(self, didReceive: url_response, cacheStoragePolicy: .allowed)
                self.client!.urlProtocol(self, didLoad: response.body)
                self.client!.urlProtocolDidFinishLoading(self)
                return
            }

            self.client!.urlProtocol(self, didFailWithError: ShalonErrors.NoContents)
        }
    }

    override func stopLoading() {
        loadingShouldStop = true
    }
}
