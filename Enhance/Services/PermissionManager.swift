import Photos

class PermissionManager {
    @Published var isAuthorized = false
    @Published var isDenied = false
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.applyStatus(status)
                
                switch status {
                case .authorized, .limited:
                    completion?(true)
                case .denied, .restricted:
                    completion?(false)
                default:
                    completion?(false)
                }
            }
        }
    }
    
    func checkStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        applyStatus(status)
    }
    
    private func applyStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            isAuthorized = true
            isDenied = false
        case .denied, .restricted:
            isAuthorized = false
            isDenied = true
        default:
            isAuthorized = false
            isDenied = false
        }
    }
}
