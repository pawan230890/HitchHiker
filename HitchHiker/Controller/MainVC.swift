//
//  MainVC.swift
//  HitchHiker
//
//  Created by Vibhanshu Vaibhav on 06/12/17.
//  Copyright © 2017 Vibhanshu Vaibhav. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import Firebase
import RevealingSplashView

let appDelegate = UIApplication.shared.delegate as? AppDelegate
let currentUserId = Auth.auth().currentUser?.uid

enum AnnotationType {
    case pickup
    case destination
 }

enum ButtonAction {
    case requestRide
    case getDirectionsToPassenger
    case getDirectionToDestination
    case startTrip
    case endTrip
}

class MainVC: UIViewController, Alertable {
    
    @IBOutlet weak var actionButton: RoundedShadowButton!
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var centerMapButton: UIButton!
    @IBOutlet weak var topView: GradientView!
    @IBOutlet weak var topViewHeight: NSLayoutConstraint!
    @IBOutlet weak var destinationTextField: UITextField!
    @IBOutlet weak var destinationCircle: RoundImageView!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var userImage: RoundImageView!
    @IBOutlet weak var locationPanelView: RoundedShadowView!
    
    var locationManager = CLLocationManager()
    let authorizationStatus = CLLocationManager.authorizationStatus()
    let regionRadius: CLLocationDistance = 500
    
    let tableView = UITableView()
    var route: MKRoute?
    
    var initialLoad = true
    var matchingItems = [MKMapItem]()
    
    var actionForButton: ButtonAction = .requestRide
    
    var driverObserverHandle: UInt = 0
    var passengerObserverHandle: UInt = 1
    
    func isPickupModeEnabled() {
        DataService.instance.driverPickupEnabled(driverKey: currentUserId!) { (enabled) in
            if enabled {
                self.actionButton.setTitle("PICKUP ENABLED", for: .normal)
            } else {
                self.actionButton.setTitle("PICKUP DISABLED", for: .normal)
            }
            self.actionButton.isHidden = false
        }
    }
    
    func putDriverAnnotation() {
        DataService.instance.REF_DRIVERS.removeObserver(withHandle: driverObserverHandle)
        driverObserverHandle = DataService.instance.REF_DRIVERS.observe(.value) { (snapshot) in
            DataService.instance.passengerIsOnTrip(passengerKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if !isOnTrip {
                    self.loadDriverAnnotation()
                }
            })
        }
    }
    
    func putPassengerAnnotation() {
        DataService.instance.REF_USERS.removeObserver(withHandle: passengerObserverHandle)
        passengerObserverHandle = DataService.instance.REF_USERS.observe(.value) { (snapshot) in
            self.loadPassengerAnnotation()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        for subview in view.subviews {
            if subview.tag == 21 {
                subview.removeFromSuperview()
            }
        }
        cancelButton.alpha = 0.0
        actionButton.isHidden = true
        
        if Auth.auth().currentUser != nil {
            userImage.isHidden = false
            if userIsDriver {
                userImage.image = UIImage(named: DRIVER_ANNOTATION)
                locationPanelView.isHidden = true
                topViewHeight.constant = 100
                actionButton.isUserInteractionEnabled = false
                actionButton.setTitle("", for: .normal)
                
                isPickupModeEnabled()
                
                DataService.instance.REF_TRIPS.observe(.childRemoved, with: { (removedTripSnapshot) in
                    guard let removedDriverKey = removedTripSnapshot.childSnapshot(forPath: DRIVER_KEY).value as? String else { return }
                    if removedDriverKey == currentUserId! {
                        self.mapView.removeOverlays(self.mapView.overlays)
                        self.removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: false, forDestinationAnnotation: true)
                        self.putPassengerAnnotation()
                        self.isPickupModeEnabled()
                        self.actionButton.isUserInteractionEnabled = false
                        self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                    }
                })
                
                DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                    if isOnTrip {
                        DataService.instance.REF_USERS.removeObserver(withHandle: self.passengerObserverHandle)
                        self.removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: true, forDestinationAnnotation: false)
                        
                        DataService.instance.REF_TRIPS.observeSingleEvent(of: .value, with: { (tripsSnapshot) in
                            guard let tripsSnapshot = tripsSnapshot.children.allObjects as? [DataSnapshot] else { return }
                            for trip in tripsSnapshot {
                                if trip.childSnapshot(forPath: DRIVER_KEY).value as! String == currentUserId! {
                                    let pickupCoordinateArray = trip.childSnapshot(forPath: PICKUP_COORDINATES).value as! NSArray
                                    let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                                    let pickupPlacemark = MKPlacemark(coordinate: pickupCoordinate)

                                    self.dropPin(forPlacemark: pickupPlacemark)
                                    self.showRoute(forOriginMapItem: nil, andDestinationMapItem: MKMapItem(placemark: pickupPlacemark))
                                    
                                    self.setCustomRegion(forAnnotationType: .pickup, withCoordinate: pickupCoordinate)

                                    self.actionForButton = .getDirectionsToPassenger
                                    
                                    self.actionButton.setTitle(GET_DIRECTIONS, for: .normal)
                                    self.actionButton.isUserInteractionEnabled = true

                                    self.cancelButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
                                }
                            }
                        })
                    }
                })
            } else {
                userImage.image = UIImage(named: PASSENGER_ANNOTATION)
                
                connectUserAndDriver()
                
                DataService.instance.REF_TRIPS.observe(.childRemoved, with: { (removedTripSnapshot) in
                    if removedTripSnapshot.key == currentUserId! {
                        self.removeAnnotationAndOverlays(forDriverAnnotation: true, forPassengerAnnotation: false, forDestinationAnnotation: true)
                        
                        self.putDriverAnnotation()
                        
                        self.matchingItems = []
                        self.tableView.reloadData()
                        
                        self.destinationTextField.text = ""
                        self.destinationTextField.isUserInteractionEnabled = true
                        
                        self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                        
                        self.actionButton.animate(shouldLoad: false, withMessage: REQUEST_RIDE)
                        self.actionButton.isHidden = true
                    }
                })
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        locationManager.delegate = self
        destinationTextField.delegate = self
        
        configureLocationServices()
        
        if Auth.auth().currentUser != nil {
            if userIsDriver {
                DataService.instance.driverPickupEnabled(driverKey: currentUserId!, handler: { (enabled) in
                    if enabled {
                        self.putPassengerAnnotation()
                    } else {
                        DataService.instance.REF_USERS.removeObserver(withHandle: self.passengerObserverHandle)
                        self.removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: true, forDestinationAnnotation: false)
                    }
                })
                
                DataService.instance.driverIsAvailable(key: currentUserId!, handler: { (available) in
                    if available {
                        DataService.instance.observeTrips(handler: { (tripDict) in
                            guard let tripDict = tripDict else { return }
                            let pickupCoordinates = tripDict[PICKUP_COORDINATES] as! NSArray
                            let passengerKey = tripDict[PASSENGER_KEY] as! String
                            let pickupVC = self.storyboard?.instantiateViewController(withIdentifier: "PickupVC") as! PickupVC
                            pickupVC.initData(pickupCoordinate: CLLocationCoordinate2DMake(pickupCoordinates[0] as! CLLocationDegrees, pickupCoordinates[1] as! CLLocationDegrees), passengerKey: passengerKey)
                            self.present(pickupVC, animated: true, completion: nil)
                        })
                    } else {
                        DataService.instance.removeTripObserver()
                    }
                })
            } else {
                putDriverAnnotation()
            }
        }
        addRevealViewController()
        addSplashView()
    }
    
    func addRevealViewController() {
        menuButton.addTarget(self.revealViewController(), action: #selector(SWRevealViewController.revealToggle(_:)), for: .touchUpInside)
        self.view.addGestureRecognizer(self.revealViewController().panGestureRecognizer())
        self.view.addGestureRecognizer(self.revealViewController().tapGestureRecognizer())
    }
    
    func addSplashView() {
        let revealingSplashView = RevealingSplashView(iconImage: UIImage(named: "launchScreenIcon")!, iconInitialSize: CGSize(width: 80, height: 80), backgroundColor: .white)
        self.view.addSubview(revealingSplashView)
        revealingSplashView.animationType = .heartBeat
        revealingSplashView.startAnimation()
        
        revealingSplashView.heartAttack = true
    }
    
    func loadPassengerAnnotation() {
        DataService.instance.REF_USERS.observeSingleEvent(of: .value) { (snapshot) in
            guard let passengerSnapshot = snapshot.children.allObjects as? [DataSnapshot] else { return }
            
            for user in passengerSnapshot {
                guard let userLocation = user.childSnapshot(forPath: COORDINATES).value as? NSArray else { return }
                let userCoordinates = CLLocationCoordinate2D(latitude: userLocation[0] as! CLLocationDegrees, longitude: userLocation[1] as! CLLocationDegrees)
                
                let isVisible = self.mapView.annotations.contains(where: { (annotation) -> Bool in
                    if let userAnnotation = annotation as? PassengerAnnotation {
                        if userAnnotation.key == user.key {
                            userAnnotation.update(annotationPosition: userAnnotation, withCoordinate: userCoordinates)
                            return true
                        }
                    }
                    return false
                })
                
                if !isVisible {
                    let userAnnotation = PassengerAnnotation(coordinate: userCoordinates, key: user.key)
                    self.mapView.addAnnotation(userAnnotation)
                }
            }
        }
    }
    
    func loadDriverAnnotation() {
        DataService.instance.REF_DRIVERS.observeSingleEvent(of: .value, with: { (snapshot) in
            guard let driverSnapshot = snapshot.children.allObjects as? [DataSnapshot] else { return }
            
            for driver in driverSnapshot {
                if driver.childSnapshot(forPath: DRIVER_PICKUP_ENABLED).value as! Bool == true {
                    guard let driverLocation = driver.childSnapshot(forPath: COORDINATES).value as? NSArray else { return }
                    let driverCoordinates = CLLocationCoordinate2D(latitude: driverLocation[0] as! CLLocationDegrees, longitude: driverLocation[1] as! CLLocationDegrees)
                    
                    let isVisible = self.mapView.annotations.contains(where: { (annotation) -> Bool in
                        if let driverAnnotation = annotation as? DriverAnnotation {
                            if driverAnnotation.key == driver.key {
                                driverAnnotation.update(annotationPosition: driverAnnotation, withCoordinate: driverCoordinates)
                                return true
                            }
                        }
                        return false
                    })
                    
                    if !isVisible {
                        let driverAnnotation = DriverAnnotation(coordinate: driverCoordinates, key: driver.key)
                        self.mapView.addAnnotation(driverAnnotation)
                    }
                } else {
                    for annotation in self.mapView.annotations where annotation.isKind(of: DriverAnnotation.self) {
                        guard let annotation = annotation as? DriverAnnotation else { return }
                        if annotation.key == driver.key {
                            self.mapView.removeAnnotation(annotation)
                        }
                    }
                }
            }
        })
    }
    
    func connectUserAndDriver() {
        DataService.instance.REF_TRIPS.child(currentUserId!).observe(.value) { (tripSnapshot) in
            guard let tripDict = tripSnapshot.value as? Dictionary<String, Any> else { return }
            
            if tripDict[TRIP_IS_ACCEPTED] as! Bool == true {
                let pickupCoordinateArray = tripDict[PICKUP_COORDINATES] as! NSArray
                let pickupCoordinates = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                let driverKey = tripDict[DRIVER_KEY] as! String
                let pickupPlacemark = MKPlacemark(coordinate: pickupCoordinates)
                
                DataService.instance.REF_DRIVERS.child(driverKey).child(COORDINATES).observeSingleEvent(of: .value, with: { (snapshot) in
                    let driverCoordinateArray = snapshot.value as! NSArray
                    let driverCoordinates = CLLocationCoordinate2D(latitude: driverCoordinateArray[0] as! CLLocationDegrees, longitude: driverCoordinateArray[1] as! CLLocationDegrees)
                    let driverPlacemark = MKPlacemark(coordinate: driverCoordinates)
                    let driverAnnotation = DriverAnnotation(coordinate: driverCoordinates, key: DRIVER)
                    
                    self.mapView.addAnnotation(driverAnnotation)
                    self.showRoute(forOriginMapItem: MKMapItem(placemark: driverPlacemark), andDestinationMapItem: MKMapItem(placemark: pickupPlacemark))
                    
                    self.actionButton.animate(shouldLoad: false, withMessage: DRIVER_COMING)
                    self.actionButton.isUserInteractionEnabled = false
                })
                
                if tripDict[TRIP_IN_PROGRESS] as! Bool == true {
                    self.removeAnnotationAndOverlays(forDriverAnnotation: true, forPassengerAnnotation: false, forDestinationAnnotation: true)
                    
                    let destinationCoordinateArray = tripDict[DESTINATION_COORDINATES] as! NSArray
                    let destinationCoordinates = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                    let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinates)
                    
                    self.dropPin(forPlacemark: destinationPlacemark)
                    self.showRoute(forOriginMapItem: MKMapItem(placemark: pickupPlacemark), andDestinationMapItem: MKMapItem(placemark: destinationPlacemark))
                    
                    self.actionButton.setTitle(ON_TRIP, for: .normal)
                }
            }
        }
    }
    
    
    func buttonSelector(forAction action: ButtonAction) {
        switch action {
        case .requestRide:
            if destinationTextField.text != "" {
                DataService.instance.updateTripWithCoordinates(forPassengerKey: currentUserId!)
                cancelButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
                destinationTextField.isUserInteractionEnabled = false
                actionButton.animate(shouldLoad: true, withMessage: nil)
            }
            break
        case .getDirectionsToPassenger:
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    DataService.instance.REF_TRIPS.child(tripKey!).child(PICKUP_COORDINATES).observeSingleEvent(of: .value, with: { (pickupCoordinateSnapshot) in
                        guard let pickupCoordinateArray = pickupCoordinateSnapshot.value as? NSArray else { return }
                        let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                        let pickupMapItem = MKMapItem(placemark: MKPlacemark(coordinate: pickupCoordinate))
                        
                        pickupMapItem.name = "Passenger Pickup Point"
                        pickupMapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    })
                }
            })
            break
        case .startTrip:
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripkey) in
                if isOnTrip {
                    self.mapView.removeOverlays(self.mapView.overlays)
                    
                    DataService.instance.REF_TRIPS.child(tripkey!).updateChildValues([TRIP_IN_PROGRESS: true])
                    
                    DataService.instance.REF_TRIPS.child(tripkey!).child(DESTINATION_COORDINATES).observeSingleEvent(of: .value, with: { (coordinateSnapshot) in
                        let destinationCoordinateArray = coordinateSnapshot.value as! NSArray
                        let destinationCoordinate = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)
                        
                        self.dropPin(forPlacemark: destinationPlacemark)
                        self.showRoute(forOriginMapItem: nil, andDestinationMapItem: MKMapItem(placemark: destinationPlacemark))
                        
                        self.setCustomRegion(forAnnotationType: .destination, withCoordinate: destinationCoordinate)
                        
                        self.actionForButton = .getDirectionToDestination
                        self.actionButton.setTitle(GET_DIRECTIONS, for: .normal)
                    })
                }
            })
            break
        case .getDirectionToDestination:
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    DataService.instance.REF_TRIPS.child(tripKey!).child(DESTINATION_COORDINATES).observeSingleEvent(of: .value, with: { (destinationCoordinateSnapshot) in
                        guard let destinationCoordinateArray = destinationCoordinateSnapshot.value as? NSArray else { return }
                        let destinationCoordinate = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                        let destinationMapItem = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
                        
                        destinationMapItem.name = "Passenger Destination"
                        destinationMapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    })
                }
            })
            break
        case .endTrip:
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    DataService.instance.cancelTrip(withPassengerKey: tripKey!, andDriverKey: driverKey!)
                }
            })
             break
        }
    }
    
    @IBAction func centerMapButtonPressed(_ sender: Any) {
        if mapView.overlays.count > 0 {
            self.zoomToFitAnnotations(fromMapView: self.mapView)
        } else {
            self.centerMapOnUserLocation()
        }
    }
    
    @IBAction func actionButtonPressed(_ sender: Any) {
        buttonSelector(forAction: actionForButton)
    }
    
    @IBAction func cancelTripButtonPressed(_ sender: Any) {
        actionButton.isUserInteractionEnabled = true
        destinationCircle.changeColour(colour: #colorLiteral(red: 0.8235294118, green: 0.8235294118, blue: 0.8235294118, alpha: 1), withDuration: 0.2)
        centerMapOnUserLocation()
        if userIsDriver {
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    DataService.instance.cancelTrip(withPassengerKey: tripKey!, andDriverKey: driverKey!)
                }
            })
            self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
        } else {
            DataService.instance.passengerIsOnTrip(passengerKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    if driverKey != nil {
                        DataService.instance.cancelTrip(withPassengerKey: tripKey!, andDriverKey: driverKey!)
                    } else {
                        DataService.instance.cancelTrip(withPassengerKey: tripKey!, andDriverKey: nil)
                    }
                }
            })
            
            destinationTextField.text = ""
            destinationTextField.isUserInteractionEnabled = true
            
            cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
            actionButton.isHidden = true
        }
    }
}

// MKMapView Delegates

extension MainVC: MKMapViewDelegate {
    
    func centerMapOnUserLocation() {
        guard let coordinate = locationManager.location?.coordinate else { return }
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(coordinate, regionRadius * 2.0, regionRadius * 2.0)
        mapView.setRegion(coordinateRegion, animated: false)
        mapView.setUserTrackingMode(.follow, animated: true)
        self.centerMapButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
    }
    
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        if initialLoad {
            centerMapOnUserLocation()
            initialLoad = false
        }
    }
    
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        if Auth.auth().currentUser != nil {
            DataService.instance.updateUserLocation(uid: currentUserId!, withCoordinates: userLocation.coordinate)
            if userIsDriver {
                let isVisible = self.mapView.annotations.contains(where: { (annotation) -> Bool in
                    if let driverAnnotation = annotation as? DriverAnnotation {
                        if driverAnnotation.key == currentUserId! {
                            driverAnnotation.update(annotationPosition: driverAnnotation, withCoordinate: userLocation.coordinate)
                            return true
                        }
                    }
                    return false
                })
                
                if !isVisible {
                    let driverAnnotation = DriverAnnotation(coordinate: userLocation.coordinate, key: currentUserId!)
                    self.mapView.addAnnotation(driverAnnotation)
                }
            } else {
                let isVisible = self.mapView.annotations.contains(where: { (annotation) -> Bool in
                    if let userAnnotation = annotation as? PassengerAnnotation {
                        if userAnnotation.key == currentUserId! {
                            userAnnotation.update(annotationPosition: userAnnotation, withCoordinate: userLocation.coordinate)
                            return true
                        }
                    }
                    return false
                })
                
                if !isVisible {
                    let userAnnotation = PassengerAnnotation(coordinate: userLocation.coordinate, key: currentUserId!)
                    self.mapView.addAnnotation(userAnnotation)
                }
            }
        } else {
            removeAnnotationAndOverlays(forDriverAnnotation: true, forPassengerAnnotation: true, forDestinationAnnotation: true)
        }
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? DriverAnnotation {
            guard let dequeuedDriverAnnotation = mapView.dequeueReusableAnnotationView(withIdentifier: DRIVER) else {
                let driverAnnotation = MKAnnotationView(annotation: annotation, reuseIdentifier: DRIVER)
                driverAnnotation.image = UIImage(named: DRIVER_ANNOTATION)
                return driverAnnotation
            }
            return dequeuedDriverAnnotation
        } else if let annotation = annotation as? PassengerAnnotation {
            guard let dequeuedPassengerAnnotation = mapView.dequeueReusableAnnotationView(withIdentifier: PASSENGER) else {
                let passengerAnnotation = MKAnnotationView(annotation: annotation, reuseIdentifier: PASSENGER)
                passengerAnnotation.image = UIImage(named: PASSENGER_ANNOTATION)
                return passengerAnnotation
            }
            return dequeuedPassengerAnnotation
        } else if let annotation = annotation as? MKPointAnnotation {
            guard let dequeuedDestinationAnnotation = mapView.dequeueReusableAnnotationView(withIdentifier: DESTINATION) else {
                let destinationAnnotation = MKAnnotationView(annotation: annotation, reuseIdentifier: DESTINATION)
                destinationAnnotation.image = UIImage(named: DESTINATION_ANNOTATION)
                return destinationAnnotation
            }
            return dequeuedDestinationAnnotation
        }
        return nil
    }
    
    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        for view in views {
            if userIsDriver {
                if view.reuseIdentifier == DRIVER {
                    view.layer.zPosition = 100
                } else {
                    view.layer.zPosition = -100
                }
            } else {
                if view.reuseIdentifier == PASSENGER {
                    view.layer.zPosition = 100
                } else {
                    view.layer.zPosition = -100
                }
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        centerMapButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let lineRenderer = MKPolylineRenderer(polyline: (route?.polyline)!)
        lineRenderer.strokeColor = #colorLiteral(red: 0.8470588235, green: 0.2784313725, blue: 0.1176470588, alpha: 1)
        lineRenderer.lineWidth = 3.0
        
        zoomToFitAnnotations(fromMapView: mapView)
        
        return lineRenderer
    }
    
    func performSearch() {
        matchingItems = []
        let request = MKLocalSearchRequest()
        request.naturalLanguageQuery = destinationTextField.text
        request.region = mapView.region
        
        let search = MKLocalSearch(request: request)
        search.start { (response, error) in
            if error != nil {
                self.destinationTextField.text = ""
                self.view.endEditing(true)
                self.showAlert((error?.localizedDescription)!)
                self.shouldPresent(false)
                print("Error in searching: \(error.debugDescription)")
            } else if response?.mapItems.count == 0 {
                print("No results for the query")
            } else {
                for mapItems in response!.mapItems {
                    self.matchingItems.append(mapItems)
                    self.shouldPresent(false)
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    func dropPin(forPlacemark placemark: MKPlacemark) {
        removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: false, forDestinationAnnotation: true)
        
        let destinationAnnotation = MKPointAnnotation()
        destinationAnnotation.coordinate = placemark.coordinate
        mapView.addAnnotation(destinationAnnotation)
    }
    
    func showRoute(forOriginMapItem originMapItem: MKMapItem?, andDestinationMapItem destinationMapItem: MKMapItem) {
        mapView.removeOverlays(mapView.overlays)
        let request = MKDirectionsRequest()
        if originMapItem == nil {
            request.source = MKMapItem.forCurrentLocation()
        } else {
            request.source = originMapItem
        }
        request.destination = destinationMapItem
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        
        let directions = MKDirections(request: request)
        directions.calculate { (response, error) in
            guard let response = response else {
                self.showAlert((error?.localizedDescription)!)
                self.shouldPresent(false)
                self.removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: false, forDestinationAnnotation: true)
                appDelegate?.window?.rootViewController?.shouldPresent(false)
                print("Error in calculating route: \(error.debugDescription)")
                return
            }
            if self.mapView.overlays.count == 0 {
                self.route = response.routes[0]
                self.mapView.add((self.route?.polyline)!)
            }
            self.shouldPresent(false)
            appDelegate?.window?.rootViewController?.shouldPresent(false)
        }
    }
    
    func zoomToFitAnnotations(fromMapView mapView: MKMapView) {
        if mapView.annotations.count == 0 {
            return
        }
        
        guard let mapRect = route?.polyline.boundingMapRect else {
            centerMapOnUserLocation()
            return
        }
        
        mapView.setVisibleMapRect(mapRect, edgePadding: UIEdgeInsetsMake(180, 60, 180, 60), animated: true)
        centerMapButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
    }
    
    func removeAnnotationAndOverlays(forDriverAnnotation driver: Bool, forPassengerAnnotation passenger: Bool, forDestinationAnnotation destination: Bool) {
        mapView.removeOverlays(mapView.overlays)
        centerMapOnUserLocation()
        
        if driver {
            for annotation in mapView.annotations where annotation.isKind(of: DriverAnnotation.self) {
                mapView.removeAnnotation(annotation)
            }
        }
        
        if passenger {
            for annotation in mapView.annotations where annotation.isKind(of: PassengerAnnotation.self) {
                mapView.removeAnnotation(annotation)
            }
        }
        
        if destination {
            for annotation in mapView.annotations where annotation.isKind(of: MKPointAnnotation.self) {
                mapView.removeAnnotation(annotation)
            }
        }
    }
    
    func setCustomRegion(forAnnotationType type: AnnotationType, withCoordinate coordinate: CLLocationCoordinate2D) {
        if type == .pickup {
            let pickupRegion = CLCircularRegion(center: coordinate, radius: 100, identifier: PICKUP)
            locationManager.startMonitoring(for: pickupRegion)
        } else if type == .destination {
            let destinationRegion = CLCircularRegion(center: coordinate, radius: 100, identifier: DESTINATION)
            locationManager.startMonitoring(for: destinationRegion)
        }
    }
}

// CLLocationManager Delegates

extension MainVC: CLLocationManagerDelegate {
    func configureLocationServices() {
        if authorizationStatus == .notDetermined || authorizationStatus == .denied {
            locationManager.requestAlwaysAuthorization()
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if userIsDriver {
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!) { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    if region.identifier == PICKUP {
                        self.actionForButton = .startTrip
                        self.actionButton.setTitle(START_TRIP, for: .normal)
                    } else if region.identifier == DESTINATION {
                        self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                        self.cancelButton.isHidden = true
                        self.actionForButton = .endTrip
                        self.actionButton.setTitle(END_TRIP, for: .normal)
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if userIsDriver {
            DataService.instance.driverIsOnTrip(driverKey: currentUserId!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip {
                    if region.identifier == PICKUP {
                        self.actionForButton = .getDirectionsToPassenger
                        self.actionButton.setTitle(GET_DIRECTIONS, for: .normal)
                    } else if region.identifier == DESTINATION {
                        self.actionForButton = .getDirectionToDestination
                        self.actionButton.setTitle(GET_DIRECTIONS, for: .normal)
                    }
                }
            })
        }
    }
}

// UITextField Delegates

extension MainVC: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        tableView.frame = CGRect(x: 20, y: view.frame.height, width: view.frame.width - 40, height: view.frame.height - 160)
        tableView.layer.cornerRadius = 5.0
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "locationCell")
        
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.tag = 18
        tableView.rowHeight = 60
        
        view.addSubview(tableView)
        animateTableView(shouldShow: true)
        
        destinationCircle.changeColour(colour: .red, withDuration: 0.2)
        
        if textField.text != "" {
            textField.text = ""
            matchingItems = []
            tableView.reloadData()
            
            actionButton.isHidden = true
            
            DataService.instance.REF_USERS.child(currentUserId!).child(DESTINATION_COORDINATES).removeValue()
            
            removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: false, forDestinationAnnotation: true)
        }
        locationManager.delegate = self
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        if textField.text == "" {
            matchingItems = []
            tableView.reloadData()
        } else {
            shouldPresent(true)
            performSearch()
        }
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField.text == "" {
            putDriverAnnotation()
            destinationCircle.changeColour(colour: #colorLiteral(red: 0.8235294118, green: 0.8235294118, blue: 0.8235294118, alpha: 1), withDuration: 0.2)
            actionButton.isHidden = true
        }
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        matchingItems = []
        tableView.reloadData()
        
        actionButton.isHidden = true
        putDriverAnnotation()
        
        removeAnnotationAndOverlays(forDriverAnnotation: false, forPassengerAnnotation: false, forDestinationAnnotation: true)
        return true
    }
    
    func animateTableView(shouldShow: Bool) {
        if shouldShow {
            UIView.animate(withDuration: 0.2) {
                self.tableView.frame = CGRect(x: 20, y: 160, width: self.view.frame.width - 40, height: self.view.frame.height - 160)
            }
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.tableView.frame = CGRect(x: 20, y: self.view.frame.height, width: self.view.frame.width - 40, height: self.view.frame.height - 200)
            }, completion: { (complete) in
                for subview in self.view.subviews {
                    if subview.tag == 18 {
                        subview.removeFromSuperview()
                    }
                }
            })
        }
    }
}

// UITableView Delegates

extension MainVC: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return matchingItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "locationCell")
        let mapItem = matchingItems[indexPath.row]
        cell.textLabel?.text = mapItem.name
        cell.detailTextLabel?.text = mapItem.placemark.title
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        DataService.instance.REF_DRIVERS.removeObserver(withHandle: driverObserverHandle)
        shouldPresent(true)
        let selectedItem = matchingItems[indexPath.row]
        let destinationPlacemark = matchingItems[indexPath.row].placemark
        
        locationManager.stopUpdatingLocation()
        mapView.showsUserLocation = false
        
        locationManager.delegate = nil
        
        removeAnnotationAndOverlays(forDriverAnnotation: true, forPassengerAnnotation: false, forDestinationAnnotation: false)
        
        dropPin(forPlacemark: destinationPlacemark)
        showRoute(forOriginMapItem: nil, andDestinationMapItem: selectedItem)
        DataService.instance.REF_USERS.child(currentUserId!).updateChildValues([DESTINATION_COORDINATES: [destinationPlacemark.coordinate.latitude, destinationPlacemark.coordinate.longitude]])
        
        actionButton.setTitle(RIDE_NOW, for: .normal)
        actionButton.isHidden = false
        
        view.endEditing(true)
        destinationTextField.text = tableView.cellForRow(at: indexPath)?.textLabel?.text
        animateTableView(shouldShow: false)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if tableView.numberOfRows(inSection: 0) == 0 {
            destinationTextField.text = ""
            view.endEditing(true)
            animateTableView(shouldShow: false)
        }
    }
    
}
