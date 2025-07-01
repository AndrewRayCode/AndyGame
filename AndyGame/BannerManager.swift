//
//  BannerManager.swift
//  AndyGame
//
//  Created by Andrew Ray on 6/21/25.
//

import UIKit

class BannerManager {
    
    // MARK: - Properties
    private var activeBanners: [UIView] = []
    private var bannerContainer: UIView?
    private var congratulationsBanner: UIView?
    private weak var parentView: UIView?
    
    // MARK: - Initialization
    init(parentView: UIView) {
        self.parentView = parentView
        setupBannerContainer()
    }
    
    // MARK: - Setup
    private func setupBannerContainer() {
        guard let parentView = parentView else { return }
        
        bannerContainer = UIView()
        bannerContainer?.backgroundColor = UIColor.clear
        bannerContainer?.translatesAutoresizingMaskIntoConstraints = false
        
        if let container = bannerContainer {
            parentView.addSubview(container)
            
            NSLayoutConstraint.activate([
                container.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
                container.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor, constant: -100),
                container.widthAnchor.constraint(lessThanOrEqualTo: parentView.widthAnchor, multiplier: 0.8),
                container.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
            ])
        }
    }
    
    // MARK: - Public Methods
    
    /// Show a generic banner with the given message and duration
    func showBanner(message: String, duration: TimeInterval = 2.0) {
        guard let container = bannerContainer else { return }
        
        // Create banner view
        let banner = UIView()
        banner.backgroundColor = UIColor.white
        banner.layer.cornerRadius = 12
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOffset = CGSize(width: 0, height: 2)
        banner.layer.shadowOpacity = 0.3
        banner.layer.shadowRadius = 4
        
        // Create label
        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.textColor = UIColor.black
        label.textAlignment = .center
        label.numberOfLines = 0
        
        // Add label to banner
        banner.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add banner to container
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to active banners array
        activeBanners.append(banner)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Banner constraints
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 50),
            
            // Label constraints
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
        ])
        
        // Position banner at the bottom of the stack
        if activeBanners.count > 1 {
            // Position above the previous banner
            let previousBanner = activeBanners[activeBanners.count - 2]
            banner.bottomAnchor.constraint(equalTo: previousBanner.topAnchor, constant: -10).isActive = true
        } else {
            // First banner - position at bottom of container
            banner.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
        
        // Animate in
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 50)
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [], animations: {
            banner.alpha = 1
            banner.transform = .identity
        })
        
        // Animate out after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.removeBanner(banner)
        }
    }
    
    // MARK: - Private Methods
    
    /// Remove a specific banner
    private func removeBanner(_ banner: UIView) {
        UIView.animate(withDuration: 0.3, animations: {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: -30)
        }, completion: { _ in
            banner.removeFromSuperview()
            if let index = self.activeBanners.firstIndex(of: banner) {
                self.activeBanners.remove(at: index)
            }
        })
    }
}
