import CoreLocation
import Foundation

/// Grabs one location reading and turns it into a place name for the payment's
/// "place" field. Degrades to a caption when the user has no location access,
/// so a denied permission never blocks saving an operation.
@MainActor
final class LocationProvider: NSObject, ObservableObject {
    struct Reading: Equatable {
        var name: String
        var latitude: Double
        var longitude: Double
    }

    @Published private(set) var isLocating = false
    @Published private(set) var reading: Reading?
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        errorMessage = nil
        reading = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .denied, .restricted:
            fail(String(localized: "location.location_access_is_disabled_in"))
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            manager.requestLocation()
        }
    }

    fileprivate func finish(with location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                let place = placemarks?.first
                let parts = [place?.name, place?.locality].compactMap { $0 }.filter { !$0.isEmpty }
                let name = parts.joined(separator: ", ")
                self.isLocating = false
                self.reading = Reading(
                    name: name.isEmpty ? String(localized: "common.my_location") : name,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
        }
    }

    fileprivate func fail(_ message: String) {
        isLocating = false
        errorMessage = message
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.isLocating { manager.requestLocation() }
            case .denied, .restricted:
                if self.isLocating { self.fail(String(localized: "location.location_access_is_disabled_in")) }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.finish(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.fail(String(localized: "location.couldnt_determine_your_location"))
        }
    }
}
