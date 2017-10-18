import Foundation

class ShalonURLProtocol : URLProtocol {
    var loadingShouldStop: Bool = false

    struct ShalonProxy {
        let hostname : String
        let port : UInt16
    }

    struct ShalonParams {
        let proxies : [ShalonProxy]
        let requestUrl : URL
    }

    class func parseShalonParams(from url: URL) -> ShalonParams? {
        var numProxies : Int
        var shalonProxies : [ShalonProxy] = []

        let urlScheme = url.scheme!.lowercased()
        let sCount = urlScheme.substring(from: urlScheme.range(of: "http")!.upperBound).characters.count

        // 1 to 3 proxies (httpss:// to httpssss://) supported
        guard (2...4).contains(sCount) else {
            return nil
        }

        numProxies = sCount - 1

        let urlString = url.absoluteString
        // The URL string, withouth the scheme part!
        let baseString = urlString.substring(from: urlString.range(of: "://")!.upperBound)
        // httpss://proxy:port/destination:port/index.html
        let components = baseString.components(separatedBy: "/")
        assert(components.count >= numProxies, "Too few proxies specified!")

        for i in 0..<numProxies {
            let ithProxy : String = components[i]
            assert(ithProxy =~ "^[a-zA-Z0-9\\.]*\\:\\d+$", "Incorrect format for proxy specification")

            let proxyInfo = ithProxy.components(separatedBy: ":")
            assert(proxyInfo.count == 2, "Extracted proxy information incomplete")

            let shalonProxy = ShalonProxy(hostname: proxyInfo[0], port: UInt16(proxyInfo[1])!)
            shalonProxies.append(shalonProxy)
        }

        // The requestUrl is now simply those components that were not used before,
        // along with the https:// scheme
        let requestUrl = URL(string: "https://" + components[numProxies..<components.count].joined(separator: "/"))
        if let actualUrl = requestUrl {
            print(shalonProxies)
            print(actualUrl)
            return ShalonParams(proxies: shalonProxies, requestUrl: actualUrl)
        }

        return nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if let url = request.url {
            let shalonParameters = parseShalonParams(from: url)
            if shalonParameters != nil {
                print("Shalon will handle request")
                return true
            } else {
                print("Shalon will not handle request")
                return false
            }
        }

        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    enum ShalonErrors : Error {
        case NotImplemented
        case UnknownHTTPMethod
        case NoContents
    }

    override func startLoading() {
        let shalonParameters = ShalonURLProtocol.parseShalonParams(from: request.url!)
        assert(shalonParameters != nil)

        print(shalonParameters!.requestUrl)

        let target = Target(withHostname: shalonParameters!.requestUrl.host!, andPort: 443)!
        let shalon = Shalon(withTarget: target)

        // Add Shalon layers from parameters
        for proxy in shalonParameters!.proxies {
            shalon.addLayer(Target(withHostname: proxy.hostname, andPort: proxy.port)!)
        }

        let optionalMethod = Method(rawValue: request.httpMethod!.uppercased())
        guard optionalMethod != nil else {
            client!.urlProtocol(self, didFailWithError: ShalonErrors.UnknownHTTPMethod)
            return
        }

        shalon.issue(request: Request(withMethod: optionalMethod!, andUrl: shalonParameters!.requestUrl)!) {
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
                // Convert internal response type to URLResponse
                let url_response = HTTPURLResponse(url: self.request.url!,
                                                   statusCode: Int(response.status.rawValue),
                                                   httpVersion: "HTTP/1.1",
                                                   headerFields: response.headers)
                self.client!.urlProtocol(self, didReceive: url_response!, cacheStoragePolicy: .allowed)
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
