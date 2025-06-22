//
//  GameViewController.swift
//  AndyGame
//
//  Created by Andrew Ray on 6/21/25.
//

import UIKit
import QuartzCore
import SceneKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create a new scene
        let scene = SCNScene()
        
        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        
        // place the camera for top-down view - closer to see the cylinders
        cameraNode.position = SCNVector3(x: 0, y: 15, z: 0)
        cameraNode.eulerAngles = SCNVector3(x: -Float.pi/2, y: 0, z: 0) // Look down
        
        // create and add a light to the scene - brighter and closer
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.light!.intensity = 1000 // Brighter light
        lightNode.position = SCNVector3(x: 0, y: 10, z: 0)
        scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene - brighter
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.intensity = 500 // Brighter ambient light
        ambientLightNode.light!.color = UIColor.lightGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        // Create cylinder array: 12 columns (x-axis) by 8 rows (z-axis)
        let cylinderRadius: Float = 0.5
        let cylinderHeight: Float = 0.2
        let spacing: Float = 1.5 // Increased spacing for better visibility
        
        print("Creating cylinder array: 12x8")
        
        for row in 0..<8 {
            for col in 0..<12 {
                // Create cylinder geometry
                let cylinderGeometry = SCNCylinder(radius: CGFloat(cylinderRadius), height: CGFloat(cylinderHeight))
                
                // Create material - brighter color
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemBlue
                material.specular.contents = UIColor.white
                material.lightingModel = .physicallyBased
                cylinderGeometry.materials = [material]
                
                // Create cylinder node
                let cylinderNode = SCNNode(geometry: cylinderGeometry)
                
                // Position cylinders in a grid
                // Center the grid around origin
                let startX = Float(-(12 - 1)) * spacing / 2
                let startZ = Float(-(8 - 1)) * spacing / 2
                
                let xPos = startX + Float(col) * spacing
                let zPos = startZ + Float(row) * spacing
                
                cylinderNode.position = SCNVector3(
                    x: xPos,
                    y: cylinderHeight / 2, // Place on ground level
                    z: zPos
                )
                
                // Add to scene
                scene.rootNode.addChildNode(cylinderNode)
                
                // Add "L" shape on top of the cylinder
                let lThickness: Float = 0.05
                let lLength: Float = 0.45
                
                // Vertical part of "L" (along z-axis)
                let verticalLGeometry = SCNCylinder(radius: CGFloat(lThickness), height: CGFloat(lLength))
                let verticalLMaterial = SCNMaterial()
                verticalLMaterial.diffuse.contents = UIColor.orange
                verticalLGeometry.materials = [verticalLMaterial]
                
                let verticalLNode = SCNNode(geometry: verticalLGeometry)
                verticalLNode.position = SCNVector3(
                    x: 0,
                    y: cylinderHeight + lLength/2,
                    z: -lLength/2
                )
                verticalLNode.eulerAngles = SCNVector3(x: -Float.pi / 2, y: 0, z: 0) // Rotate to be horizontal
                cylinderNode.addChildNode(verticalLNode)
                
                // Horizontal part of "L" (along x-axis)
                let horizontalLGeometry = SCNCylinder(radius: CGFloat(lThickness), height: CGFloat(lLength))
                let horizontalLMaterial = SCNMaterial()
                horizontalLMaterial.diffuse.contents = UIColor.orange
                horizontalLGeometry.materials = [horizontalLMaterial]
                
                let horizontalLNode = SCNNode(geometry: horizontalLGeometry)
                horizontalLNode.position = SCNVector3(
                    x: lLength/2,
                    y: cylinderHeight + lLength/2,
                    z: 0
                )
                horizontalLNode.eulerAngles = SCNVector3(x: Float.pi/2, y: Float.pi/2, z: 0)
                cylinderNode.addChildNode(horizontalLNode)
            }
        }

        // retrieve the SCNView
        let scnView = self.view as! SCNView
        
        // set the scene to the view
        scnView.scene = scene
        
        // allows the user to manipulate the camera
        scnView.allowsCameraControl = true
        
        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        // configure the view
        scnView.backgroundColor = UIColor.black
        
        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        
        print("Scene setup complete. Total nodes in scene: \(scene.rootNode.childNodes.count)")
    }
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        // retrieve the SCNView
        let scnView = self.view as! SCNView
        
        // check what nodes are tapped
        let p = gestureRecognize.location(in: scnView)
        let hitResults = scnView.hitTest(p, options: [:])
        // check that we clicked on at least one object
        if hitResults.count > 0 {
            // retrieved the first clicked object
            let result = hitResults[0]
            
            // get its material
            let material = result.node.geometry!.firstMaterial!
            
            // highlight it
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            
            // on completion - unhighlight
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                
                material.emission.contents = UIColor.black
                
                SCNTransaction.commit()
            }
            
            material.emission.contents = UIColor.red
            
            SCNTransaction.commit()
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

}
