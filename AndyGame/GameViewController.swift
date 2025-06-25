//
//  GameViewController.swift
//  AndyGame
//
//  Created by Andrew Ray on 6/21/25.
//

import UIKit
import QuartzCore
import SceneKit
import GLTFSceneKit

enum ROTATION: Int {
    case zero = 0
    case one = 1
    case two = 2
    case three = 3
}

struct CellPosition: Hashable {
    let row: Int
    let col: Int
}

typealias NEIGHBOR = (Int, Int)

let UP: NEIGHBOR = (0, -1)
let DOWN: NEIGHBOR = (0, 1)
let LEFT: NEIGHBOR = (-1, 0)
let RIGHT: NEIGHBOR = (1, 0)

// Matrix neighbor targeting [+-x, +-y]
let RotationNeighbors: [ROTATION: [NEIGHBOR]] = [
    // └ up right
    .zero: [UP, RIGHT],
    // ┌ right down
    .one: [RIGHT, DOWN],
    // ┐ left down
    .two: [LEFT, DOWN],
    // ┘ up left
    .three: [UP, LEFT],
]

func loadGLB(named filename: String) -> SCNScene? {
    do {
        let sceneSource = try GLTFSceneSource(named: filename)
        let scene = try sceneSource.scene()
        return scene
    } catch {
        print("Error loading GLB file: \(error.localizedDescription)")
        return nil
    }
}

class GameViewController: UIViewController {
    
    // Grid dimensions
    // vertical axis
    private let GRID_ROWS = 10
    // horizontal axis
    private let GRID_COLS = 8
    private let GRID_SPACING = 1.1
    
    private let GRID_PADDING: Float = 1.0 // Padding around the grid in world units
    
    private let CAMERA_DISTANCE: Float = 10.0
    
    private let cylinderRadius: Float = 0.5
    private let cylinderHeight: Float = 0.5
    
    // 2D array to store rotation states for each cylinder
    var rotationStates: [[Int]] = []
    
    // Dictionary to map cylinder nodes to their grid positions
    var cylinderNodes: [SCNNode: CellPosition] = [:]
    
    // Flag to track if any cylinder is currently rotating
    var isRotating = false
    
    // Store original materials to restore after rotation
    var originalMaterials: [SCNNode: SCNMaterial] = [:]
    
    // Reset button
    private var resetButton: UIButton!
    
    // Camera node reference
    private var cameraNode: SCNNode!
    
    var scene: SCNScene!
    var gridGroupNode: SCNNode!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize rotation states array
        rotationStates = Array(repeating: Array(repeating: 0, count: GRID_COLS), count: GRID_ROWS)
        
        // create a new scene
        scene = SCNScene()
        
        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        self.cameraNode = cameraNode
        
        // Create a parent group node for the entire grid
        gridGroupNode = SCNNode()
        gridGroupNode.name = "GridGroup"
        scene.rootNode.addChildNode(gridGroupNode)
        
        // Calculate grid dimensions in world space
        let gridWidth = Float(GRID_COLS) * Float(GRID_SPACING)
        let gridHeight = Float(GRID_ROWS) * Float(GRID_SPACING)
        let scnView = self.view as! SCNView
        let cameraAspect = Float(scnView.bounds.width / scnView.bounds.height)
        
        // Calculate camera view frustum dimensions
        let cameraFOV = Float(cameraNode.camera!.fieldOfView)

        let frustumHeight = 2.0 * CAMERA_DISTANCE * tan(0.5 * cameraFOV * Float.pi / Float(180.0))
        let frustumWidth = frustumHeight * cameraAspect
        
        // if the grid width is at 90, and we need to get it to 10 (frustum width)
        let scale = min(
            frustumWidth / (gridWidth + GRID_PADDING * 2), 
            frustumHeight / (gridHeight + GRID_PADDING * 2) 
        )
        gridGroupNode.scale = SCNVector3(x: scale, y: scale, z: scale)

        // Place the camera for top-down view - directly above the grid center
        cameraNode.position = SCNVector3(x: 0, y: CAMERA_DISTANCE, z: 0)
        cameraNode.eulerAngles = SCNVector3(x: -Float.pi/2, y: 0, z: 0) // Look straight down
        
        // Scale the grid to fit the screen
        updateGridScale()
        
        // create and add a light to the scene - brighter and closer
//        let lightNode = SCNNode()
//        lightNode.light = SCNLight()
//        lightNode.light!.type = .omni
//        lightNode.light!.intensity = 100 // Brighter light
//        lightNode.position = SCNVector3(x: -3, y: 20, z: -3)
//        scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene - brighter
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.intensity = 1000 // Brighter ambient light
        ambientLightNode.light!.color = UIColor.lightGray
        scene.rootNode.addChildNode(ambientLightNode)

        // Load the pipe model
        var pipeScene: SCNScene
        do {
          let sceneSource = try GLTFSceneSource(named: "art.scnassets/Pipe.glb")
            pipeScene = try sceneSource.scene()
        } catch {
          print("\(error.localizedDescription)")
          return
        }

        
        // Get the pipe node from the loaded scene
        guard let pipeNode = pipeScene.rootNode.childNodes.first else {
            print("Error: No nodes found in Pipe.glb")
            return
        }

        for row in 0..<GRID_ROWS {
            for col in 0..<GRID_COLS {
                // Create cylinder geometry
                let cylinderGeometry = SCNCylinder(radius: CGFloat(cylinderRadius), height: CGFloat(cylinderHeight))
                
                // Create material - brighter color
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.systemBlue
                material.specular.contents = UIColor.white
                material.lightingModel = .physicallyBased
                material.shininess = 1000
                cylinderGeometry.materials = [material]
                
                // Create cylinder node
                let cylinderNode = SCNNode(geometry: cylinderGeometry)
                
                // Position cylinders in a grid
                // Center the grid around origin
                let startX = Float(-(GRID_COLS - 1)) * Float(GRID_SPACING) / 2
                let startZ = Float(-(GRID_ROWS - 1)) * Float(GRID_SPACING) / 2
                
                let xPos = startX + Float(col) * Float(GRID_SPACING)
                let zPos = startZ + Float(row) * Float(GRID_SPACING)
                
                cylinderNode.position = SCNVector3(
                    x: xPos,
                    y: cylinderHeight / 2, // Place on ground level
                    z: zPos
                )
                
                // Add to scene
                gridGroupNode.addChildNode(cylinderNode)
                
                // Store mapping between cylinder node and its grid position
                cylinderNodes[cylinderNode] = CellPosition(row: row, col: col)

                let childPipe = pipeNode.clone()
                childPipe.position = SCNVector3(
                    x: 0,
                    y: cylinderHeight / 2,
                    z: 0
                )
                let childPipeScale = Float(0.25)
                childPipe.scale = SCNVector3(x: childPipeScale, y: childPipeScale, z: childPipeScale)
                childPipe.eulerAngles = SCNVector3(x: Float.pi / 2, y: 0, z: 0)
                cylinderNode.addChildNode(childPipe)
            }
        }
        
        // Randomize the initial board state
        resetBoard()

        // set the scene to the view
        scnView.scene = scene
        
        // allows the user to manipulate the camera
        scnView.allowsCameraControl = false
        
        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        // configure the view
        scnView.backgroundColor = UIColor.black
        
        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
        
        // Create and setup reset button
        setupResetButton()
        
        print("Scene setup complete. Total nodes in scene: \(scene.rootNode.childNodes.count)")
    }
    
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        print("handleTap \(isRotating)")
        // Check if any cylinder is currently rotating
        if isRotating {
            return
        }
        
        // retrieve the SCNView
        let scnView = self.view as! SCNView
        
        // check what nodes are tapped
        let p = gestureRecognize.location(in: scnView)
        let hitResults = scnView.hitTest(p, options: [:])

        // check that we clicked on at least one object
        if hitResults.count > 0 {
            // retrieved the first clicked object
            let result = hitResults[0]
            
            // Find the main cylinder node (either the tapped node itself or its parent)
            var cylinderNode = result.node
            while cylinderNode.parent != nil && cylinderNode.parent != scnView.scene?.rootNode 
                && cylinderNode.parent != gridGroupNode {
                cylinderNode = cylinderNode.parent!
            }
            
            // Get the grid position for this cylinder
            guard let position = cylinderNodes[cylinderNode] else { return }
            
            // Rotate the clicked cell
            rotateCells([position])
        }
    }

    // On initial tap, this rotates the first cell.
    // On subsequent rotation completions, this function is called with the
    // *finished* rotations   
    private func rotateCells(_ cells: [CellPosition]) {
        // Set rotating flag to prevent other taps
        isRotating = true
        updateResetButtonState()
        
        // Process each cell in the array
        for cell in cells {
            // Increment rotation state (unbounded)
            rotationStates[cell.row][cell.col] += 1
            
            // Calculate visual rotation based on state
            let rotationState = rotationStates[cell.row][cell.col]
            let visualRotation = Float(rotationState) * -Float.pi / 2 // 90 degrees per state
            
            // Find the cylinder node for this position
            guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { continue }
            
            // Store original material and change to pink during rotation
            if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
                originalMaterials[cylinderNode] = material.copy() as? SCNMaterial
                material.diffuse.contents = UIColor.systemPink
            }
            
            // Animate the rotation
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            
            cylinderNode.eulerAngles.y = visualRotation
            
            SCNTransaction.commit()
            
            print("Cylinder at (\(cell.row), \(cell.col)) rotated to state: \(rotationState)")
        }
        
        // Set up a single completion block for the entire batch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.onRotationComplete(rotatedCells: cells)
        }
    }
    
    private func findCylinderNode(at row: Int, col: Int) -> SCNNode? {
        let position = CellPosition(row: row, col: col)
        for (node, nodePosition) in cylinderNodes {
            if nodePosition == position {
                return node
            }
        }
        return nil
    }
    
    private func findConnectedNeighbors(
        x: Int,
        y: Int,
        rotation: ROTATION,
        currentRotations: [[Int]]
    ) -> [CellPosition] {
        var neighborsToRotate: [CellPosition] = []
        
        // Check each direction from this pipe
        for (dx, dy) in RotationNeighbors[rotation] ?? [] {
            let nx = x + dx
            let ny = y + dy
            
            // Check if neighbor exists on the board
            guard ny >= 0 && ny < currentRotations.count && 
                  nx >= 0 && nx < currentRotations[ny].count else { continue }
            
            let neighborUnbounded = currentRotations[ny][nx]
            let neighbor = ROTATION(rawValue: neighborUnbounded % 4) ?? .zero
            
            // Then make sure the neighbor points back at us
            let neighborPointsAtUsToo = (RotationNeighbors[neighbor] ?? []).contains { (ndx, ndy) in
                let points = nx + ndx == x && ny + ndy == y
                return points
            }
            
            if neighborPointsAtUsToo {
                neighborsToRotate.append(CellPosition(row: ny, col: nx))
            }
        }
        
        return neighborsToRotate
    }
    
    private func onRotationComplete(rotatedCells: [CellPosition]) {
        // Restore original materials
        for (node, originalMaterial) in originalMaterials {
            if let geometry = node.geometry, let material = geometry.firstMaterial {
                material.diffuse.contents = originalMaterial.diffuse.contents
            }
        }
        
        var newNeighborsToRotate: [CellPosition] = []
        // Find connected neighbors for each rotated cell
        for cell in rotatedCells {
            let currentRotation = ROTATION(rawValue: rotationStates[cell.row][cell.col] % 4) ?? .zero
            let neighbors = findConnectedNeighbors(x: cell.col, y: cell.row, rotation: currentRotation, currentRotations: rotationStates)

            if neighbors.count > 0 {
                newNeighborsToRotate.append(cell)
                newNeighborsToRotate.append(contentsOf: neighbors)
            }
        }
        
        // Deduplicate newNeighborsToRotate efficiently using a Set
        let uniqueNeighbors = Array(Set(newNeighborsToRotate))
        
        if uniqueNeighbors.count > 0 {
            print("Rotating neighbors: \(uniqueNeighbors)")
            rotateCells(uniqueNeighbors)
        } else {
            print("No more rotations")
            isRotating = false
            originalMaterials.removeAll()
            updateResetButtonState()
        }
    }
    
    private func setupResetButton() {
        resetButton = UIButton(type: .system)
        resetButton.setTitle("Reset Board", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = UIColor.systemBlue
        resetButton.layer.cornerRadius = 8
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetBoard), for: .touchUpInside)
        
        // Add button to view
        view.addSubview(resetButton)
        
        // Setup constraints
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resetButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resetButton.widthAnchor.constraint(equalToConstant: 120),
            resetButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        updateResetButtonState()
    }
    
    private func updateResetButtonState() {
        resetButton.isEnabled = !isRotating
        resetButton.alpha = isRotating ? 0.5 : 1.0
    }
    
    @objc private func resetBoard() {
        guard !isRotating else { return }
        
        // Disable interactions during reset
        isRotating = true
        
        // Create array of all cells in diagonal order (top-right to bottom-left)
        var diagonalCells: [CellPosition] = []
        for row in 0..<GRID_ROWS {
            for col in 0..<GRID_COLS {
                diagonalCells.append(CellPosition(row: row, col: col))
            }
        }
        
        // Sort cells in diagonal order (top-right to bottom-left)
        diagonalCells.sort { cell1, cell2 in
            let sum1 = cell1.row + cell1.col
            let sum2 = cell2.row + cell2.col
            if sum1 == sum2 {
                // If same diagonal, prioritize top-right (lower row, higher col)
                return cell1.row < cell2.row
            }
            return sum1 > sum2 // Higher sum = closer to top-right
        }
        
        let animationStagger = 0.005
        
        // Animate reset with staggered timing
        for (index, cell) in diagonalCells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * animationStagger) {
                self.animateSingleCellReset(cell: cell, isLast: index == diagonalCells.count - 1)
            }
        }
        
        print("Board reset started with \(diagonalCells.count) cells")
    }
    
    private func animateSingleCellReset(cell: CellPosition, isLast: Bool) {
        // Reset rotation state to 0
        let randomState = Int.random(in: 0...3)
        rotationStates[cell.row][cell.col] = randomState
        
        // Find the cylinder node for this position
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { return }
        
        // Animate the rotation back to 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        
        let visualRotation = Float(randomState) * -Float.pi / 2
        cylinderNode.eulerAngles.y = visualRotation
        
        // Reset material color to blue
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = UIColor.systemBlue
        }
        
        SCNTransaction.commit()
        
        // If this is the last cell, re-enable interactions
        if isLast {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isRotating = false
                self.updateResetButtonState()
                print("Board reset complete")
            }
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

    private func updateGridScale() {
        guard let gridGroupNode = scene?.rootNode.childNode(withName: "GridGroup", recursively: true) else { return }
        
        // Calculate grid dimensions in world space
        let gridWidth = Float(GRID_COLS) * Float(GRID_SPACING)
        let gridHeight = Float(GRID_ROWS) * Float(GRID_SPACING)
        
        // Get current screen dimensions
        let scnView = self.view as! SCNView
        let cameraAspect = Float(scnView.bounds.width / scnView.bounds.height)
        
        // Calculate camera view frustum dimensions
        let cameraFOV = Float(cameraNode.camera!.fieldOfView)
        let frustumHeight = 2.0 * CAMERA_DISTANCE * tan(0.5 * cameraFOV * Float.pi / Float(180.0))
        let frustumWidth = frustumHeight * cameraAspect
        
        // Calculate scale to fit grid within frustum
        let scale = min(
            frustumWidth / (gridWidth + GRID_PADDING * 2), 
            frustumHeight / (gridHeight + GRID_PADDING * 2) 
        )
        
        gridGroupNode.scale = SCNVector3(x: scale, y: scale, z: scale)
        
        print("Grid scaled to: \(scale) for screen aspect: \(cameraAspect)")
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            // Update grid scale when orientation changes
            self.updateGridScale()
        }, completion: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update grid scale when view layout changes (e.g., safe area changes)
        updateGridScale()
    }

}
