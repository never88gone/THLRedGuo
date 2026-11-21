import Foundation

final class HongguoBusinessRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if task.originalRequest?.value(forHTTPHeaderField: "Cookie") != nil {
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
}
