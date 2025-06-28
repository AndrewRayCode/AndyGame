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
    
    private let ROTATION_TIME = 0.6
    
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
    
    // Completion tracking for animations
    private var animationCompletionCount = 0
    private var totalAnimationsInBatch = 0
    private var currentRotatingCells: [CellPosition] = []
    
    // Store detected pipe squares
    private var pipeSquares: [[CellPosition]] = []
    
    // Square pipe interaction system
    private var clickableSquarePipes: Set<CellPosition> = []
    private var squarePipeTimers: [String: Timer] = [:]
    private var squarePipeGreenTimers: [String: Timer] = [:]
    private var squarePipeStartTime: Date?

    private let SQUARE_CLICK_MIN_WAIT = 1.0
    private let SQUARE_CLICK_MAX_WAIT = 2.0
    private let SQAURE_CLICK_TIMEOUT = 5.0
    
    // Track clicked squares for next rotation
    private var clickedSquares: [[CellPosition]] = []
    
    // Track expired squares (squares that weren't clicked in time)
    private var expiredSquares: Set<CellPosition> = []
    
    // Track squares that were clicked (to prevent them from turning gray)
    private var clickedSquarePipes: Set<CellPosition> = []
    
    // Track squares that contain cells used as rotation starters (to prevent them from becoming clickable)
    private var squaresWithStarterCells: Set<String> = []
    
    // Congratulations banner
    private var congratulationsBanner: UIView?
    
    // Reset button
    private var resetButton: UIButton!
    
    // Camera node reference
    private var cameraNode: SCNNode!
    
    // Score tracking
    private var currentScore: Int = 0
    private var highScore: Int = 0
    
    // Score display labels
    private var currentScoreLabel: UILabel!
    private var highScoreLabel: UILabel!
    
    var scene: SCNScene!
    var gridGroupNode: SCNNode!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize rotation states array
        rotationStates = Array(repeating: Array(repeating: 0, count: GRID_COLS), count: GRID_ROWS)
        
        // create a new scene
        scene = SCNScene()
        
        // Load environment map
        if let envMap = UIImage(named: "spherical.jpg") {
            scene.lightingEnvironment.contents = envMap
            scene.lightingEnvironment.intensity = 1.0
        } else {
            print("Could not load spherical.jpg as environment map")
        }
        
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
                material.metalness.contents = 1.0
                material.roughness.contents = 0.2
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

                // Add pipe model as L-shape replacement
                let childPipe = pipeNode.clone()
                makePipeMaterialsReflective(childPipe)
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
        
        // Create and setup score display
        setupScoreDisplay()
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
            
            // Find the main cylinder node (either the tapped node itself or its parent)
            var cylinderNode = result.node
            while cylinderNode.parent != nil && cylinderNode.parent != scnView.scene?.rootNode 
                && cylinderNode.parent != gridGroupNode {
                cylinderNode = cylinderNode.parent!
            }
            
            // Get the grid position for this cylinder
            guard let position = cylinderNodes[cylinderNode] else { return }
            
            // Don't allow clicking on expired (gray) pipes
            if expiredSquares.contains(position) {
                return
            }
            
            // Check if this is a clickable square pipe
            if clickableSquarePipes.contains(position) {
                // Handle square pipe click
                handleSquarePipeClick(position)
                return
            }
            
            // Normal pipe click - only allow if not rotating
            if isRotating {
                return
            }
            
            // Reset current score when a cylinder is tapped
            resetCurrentScore()
            
            // Rotate the clicked cell
            rotateCells([position], [])
        }
    }
    
    /**
     * Utility functions
     */

    // On initial tap, this rotates the first cell.
    // On subsequent rotation completions, this function is called with the
    // *finished* rotations   
    private func rotateCells(_ cells: [CellPosition], _ squareCellsToExpand: [[CellPosition]] = []) {
        // Set rotating flag to prevent other taps
        isRotating = true
        updateResetButtonState()
        detectPipeSquares()
        
        // Track squares that contain starter cells (cells that initiated this rotation)
        trackSquaresWithStarterCells(cells)
        
        // Start square pipe interaction system only if not already started
        if squarePipeStartTime == nil {
            startSquarePipeInteraction()
        }
        
        // Initialize completion tracking
        animationCompletionCount = 0
        totalAnimationsInBatch = cells.count
        currentRotatingCells = cells

        for square in squareCellsToExpand {
            let topRight = square[1]
            let bottomLeft = square[2]
            let bottomRight = square[3]
            let topLeft = square[0]
            
            // Highlight all pipes in the square as rotating
            highlightRotatingPipe(topLeft)
            highlightRotatingPipe(topRight)
            highlightRotatingPipe(bottomLeft)
            highlightRotatingPipe(bottomRight)
            
            rotationStates[topLeft.row][topLeft.col] = 3
            rotationStates[topRight.row][topRight.col] = 0
            rotationStates[bottomLeft.row][bottomLeft.col] = 2
            rotationStates[bottomRight.row][bottomRight.col] = 1
            
            animatePipeRotation(cell: topLeft, targetRotation: 3, completion: nil)
            animatePipeRotation(cell: topRight, targetRotation: 0, completion: nil)
            animatePipeRotation(cell: bottomLeft, targetRotation: 2, completion: nil)
            animatePipeRotation(cell: bottomRight, targetRotation: 1, completion: nil)
        }
        
        // Process each cell in the array
        for cell in cells {
            // Update rotation state (unbounded)
            rotationStates[cell.row][cell.col] -= 1
            
            // Add 1 point for each rotation
            addToScore(1)
            
            // Calculate visual rotation based on state
            let rotationState = rotationStates[cell.row][cell.col]

            // Highlight the pipe as rotating
            highlightRotatingPipe(cell)
            
            // Animate a pipe rotation with spring physics
            animatePipeRotation(cell: cell, targetRotation: rotationState, completion: {
                // Increment the completion counter
                self.animationCompletionCount += 1
                
                // Check if all animations in this batch are complete
                if self.animationCompletionCount >= self.totalAnimationsInBatch {
                    let cellsAndCellsInSquares = cells + squareCellsToExpand.flatMap { $0 }
                    self.onRotationComplete(rotatedCells: cellsAndCellsInSquares)
                }
            })
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

    // Get a ROTATION from an unbounded rotation state
    private func getRotation(unboundedRotation: Int) -> ROTATION {
        // Handle negative numbers properly by using ((n % 4) + 4) % 4
        let normalizedRotation = ((unboundedRotation % 4) + 4) % 4
        return ROTATION(rawValue: normalizedRotation) ?? .zero
    }
    
    private func findConnectedNeighbors(
        row: Int,
        col: Int,
    ) -> [CellPosition] {
        let rotation = getRotation(unboundedRotation: rotationStates[row][col])
        var neighborsToRotate: [CellPosition] = []
        
        // Check each direction from this pipe
        for (dx, dy) in RotationNeighbors[rotation] ?? [] {
            let nx = col + dx
            let ny = row + dy
            
            // Check if neighbor exists on the board
            guard ny >= 0 && ny < GRID_ROWS && 
                  nx >= 0 && nx < GRID_COLS else { continue }
            
            let neighbor = getRotation(unboundedRotation: rotationStates[ny][nx])
            
            // Then make sure the neighbor points back at us
            let neighborPointsAtUsToo = (RotationNeighbors[neighbor] ?? []).contains { (ndx, ndy) in
                let points = nx + ndx == col && ny + ndy == row
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
        
        // Detect pipe squares after rotation
        detectPipeSquares()
        
        var newNeighborsToRotate: [CellPosition] = []
        // Find connected neighbors for each rotated cell
        for cell in rotatedCells {
            let neighbors = findConnectedNeighbors(row: cell.row, col: cell.col)

             if neighbors.count > 0 {
                 newNeighborsToRotate.append(cell)
                 newNeighborsToRotate.append(contentsOf: neighbors)
             }
        }
        
        // Process clicked squares and add their cells to rotation
        let clickedSquareCells = processClickedSquares()
        // newNeighborsToRotate.append(contentsOf: clickedSquareCells)
        
        // Deduplicate newNeighborsToRotate efficiently using a Set
        let uniqueNeighbors = Array(Set(newNeighborsToRotate))
        
        if uniqueNeighbors.count > 0 {
//            print("Rotating neighbors: \(uniqueNeighbors)")
            // Add points for chain reaction rotations
            addToScore(uniqueNeighbors.count)
            rotateCells(uniqueNeighbors, clickedSquareCells)

//            for cell in uniqueNeighbors {
//                let cylinderNode = findCylinderNode(at: cell.row, col: cell.col)
//                if let geometry = cylinderNode?.geometry, let material = geometry.firstMaterial {
//                    material.diffuse.contents = UIColor.red
//                }
//            }
//            isRotating = false
        } else {
            isRotating = false
            originalMaterials.removeAll()
            updateResetButtonState()
            
            // Stop square pipe interaction when rotation ends
            stopSquarePipeInteraction()
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
        
        // Clear expired squares and reset their colors
        for pipe in expiredSquares {
            resetExpiredPipeColor(pipe)
        }
        expiredSquares.removeAll()
        clickedSquarePipes.removeAll()
        
        // Create array of all cells in diagonal order (top-right to bottom-left)
        var diagonalCells: [CellPosition] = []
        for row in 0..<GRID_ROWS {
            for col in 0..<GRID_COLS {
                diagonalCells.append(CellPosition(row: row, col: col))
            }
        }
        
        // Track completion of all reset animations
        var completedAnimations = 0
        let totalAnimations = diagonalCells.count
        let animationStagger = 0.005
        
        // Animate reset with staggered timing
        for (index, cell) in diagonalCells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * animationStagger) {
                self.animateSingleCellReset(
                    cell: cell, 
                    completion: {
                        completedAnimations += 1
                        if completedAnimations == totalAnimations {
                            self.isRotating = false
                            self.updateResetButtonState()
                        }
                    }
                )
            }
        }
    }

    // Animate a pipe rotation with spring physics
    private func animatePipeRotation(cell: CellPosition, targetRotation: Int, completion: (() -> Void)? = nil) {
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else {
            completion?()
            return
        }
        let visualRotation = Float(targetRotation) * -Float.pi / 2
        
        // Create springy rotation animation using CASpringAnimation
        let springAnimation = CASpringAnimation(keyPath: "eulerAngles.y")
        springAnimation.fromValue = cylinderNode.eulerAngles.y
        springAnimation.toValue = visualRotation
        springAnimation.duration = ROTATION_TIME
        springAnimation.damping = 20.0 // Spring damping (higher = less bouncy)
        springAnimation.stiffness = 400.0 // Spring stiffness (higher = faster)
        springAnimation.mass = 1.0 // Mass of the spring (higher = slower)
        springAnimation.initialVelocity = 0.5 // Initial velocity
        
        // Store completion callback
        if let completion = completion {
            springAnimation.setValue(completion, forKey: "completionCallback")
            // Set up completion tracking
            springAnimation.delegate = self
        }
        
        
        // Store reference to track completion
        let animationKey = "rotation_\(cell.row)_\(cell.col)"
        cylinderNode.addAnimation(springAnimation, forKey: animationKey)
        
        // Update the actual property
        cylinderNode.eulerAngles.y = visualRotation
    }
    
    private func animateSingleCellReset(cell: CellPosition, completion: @escaping () -> Void) {
        // Randomise rotation stat
        let randomState = Int.random(in: 0...3)
        rotationStates[cell.row][cell.col] += randomState
        
        // Force a square starting at 1,1 on the board
        if cell.row == 1 && cell.col == 1 {
            rotationStates[cell.row][cell.col] = 1
        }
        if cell.row == 1 && cell.col == 2 {
            rotationStates[cell.row][cell.col] = 2
        }
        if cell.row == 2 && cell.col == 1 {
            rotationStates[cell.row][cell.col] = 0
        }
        if cell.row == 2 && cell.col == 2 {
            rotationStates[cell.row][cell.col] = 3
        }
        let rotation = rotationStates[cell.row][cell.col]
        
        // Find the cylinder node for this position
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { 
            completion()
            return 
        }
        
        let visualRotation = Float(rotation) * -Float.pi / 2
        
        // Use springy animation for reset as well
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
        
        // Set the completion block
        SCNTransaction.completionBlock = {
            completion()
        }
        
        cylinderNode.eulerAngles.y = visualRotation
        
        // Reset material color
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = UIColor.systemBlue
        }
        
        SCNTransaction.commit()
    }
    
    
    /**
     * UI
     */
    
    private func setupScoreDisplay() {
        // Create current score label
        currentScoreLabel = UILabel()
        currentScoreLabel.text = "Score: 0"
        currentScoreLabel.textColor = .white
        currentScoreLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        currentScoreLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        currentScoreLabel.layer.cornerRadius = 8
        currentScoreLabel.layer.masksToBounds = true
        currentScoreLabel.textAlignment = .center
        
        // Create high score label
        highScoreLabel = UILabel()
        highScoreLabel.text = "High Score: 0"
        highScoreLabel.textColor = .white
        highScoreLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        highScoreLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        highScoreLabel.layer.cornerRadius = 8
        highScoreLabel.layer.masksToBounds = true
        highScoreLabel.textAlignment = .center
        
        // Add to view
        view.addSubview(currentScoreLabel)
        view.addSubview(highScoreLabel)
        
        // Setup constraints
        currentScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        highScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Current score label
            currentScoreLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            currentScoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            currentScoreLabel.widthAnchor.constraint(equalToConstant: 120),
            currentScoreLabel.heightAnchor.constraint(equalToConstant: 30),
            
            // High score label
            highScoreLabel.topAnchor.constraint(equalTo: currentScoreLabel.bottomAnchor, constant: 8),
            highScoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            highScoreLabel.widthAnchor.constraint(equalToConstant: 120),
            highScoreLabel.heightAnchor.constraint(equalToConstant: 25)
        ])
        
        updateScoreDisplay()
    }
    
    private func updateScoreDisplay() {
        currentScoreLabel.text = "Score: \(currentScore)"
        highScoreLabel.text = "High Score: \(highScore)"
    }
    
    private func addToScore(_ points: Int) {
        currentScore += points
        if currentScore > highScore {
            highScore = currentScore
        }
        updateScoreDisplay()
    }
    
    private func resetCurrentScore() {
        currentScore = 0
        updateScoreDisplay()
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

    // Recursively set PBR, metalness, roughness, and diffuse on all materials in a node tree
    private func makePipeMaterialsReflective(_ node: SCNNode) {
        if let geometry = node.geometry {
            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                material.metalness.contents = 1.0
                material.roughness.contents = 0.1
                material.diffuse.contents = UIColor.white
            }
        }
        for child in node.childNodes {
            makePipeMaterialsReflective(child)
        }
    }

    // Detect 2x2 squares formed by pipes pointing at each other
    private func detectPipeSquares() {
        pipeSquares.removeAll()
        
        // Check each possible 2x2 square on the board
        for row in 0..<(GRID_ROWS - 1) {
            for col in 0..<(GRID_COLS - 1) {
                // Check if this 2x2 area forms a square with the specific pattern
                if isSquarePattern(at: row, col: col) {
                    let squareCells = [
                        CellPosition(row: row, col: col),
                        CellPosition(row: row, col: col + 1),
                        CellPosition(row: row + 1, col: col),
                        CellPosition(row: row + 1, col: col + 1)
                    ]
                    pipeSquares.append(squareCells)
                }
            }
        }
    }
    
    // Check if a 2x2 area forms the specific square pattern
    private func isSquarePattern(at row: Int, col: Int) -> Bool {
        // Check if all cells in the 2x2 area have the correct rotations
        let topLeft = getRotation(unboundedRotation: rotationStates[row][col])
        let topRight = getRotation(unboundedRotation: rotationStates[row][col + 1])
        let bottomLeft = getRotation(unboundedRotation: rotationStates[row + 1][col])
        let bottomRight = getRotation(unboundedRotation: rotationStates[row + 1][col + 1])
        
        // Check for the specific pattern: [[.one, .two], [.zero, .three]]
        return topLeft == .one && topRight == .two && 
               bottomLeft == .zero && bottomRight == .three
    }
    
    // Start the square pipe interaction system
    private func startSquarePipeInteraction() {
        // Clear any existing timers
        stopSquarePipeInteraction()
        
        // Record start time
        squarePipeStartTime = Date()
        
        // For each square, schedule activation of the entire square
        for square in pipeSquares {
            let randomDelay = Double.random(in: SQUARE_CLICK_MIN_WAIT...SQUARE_CLICK_MAX_WAIT)
            
            let timer = Timer.scheduledTimer(withTimeInterval: randomDelay, repeats: false) { [weak self] _ in
                self?.activateSquare(square)
            }
            
            // Store timer with a unique key for the square
            let squareKey = "square_\(square[0].row)_\(square[0].col)"
            squarePipeTimers[squareKey] = timer
        }
    }
    
    // Stop the square pipe interaction system
    private func stopSquarePipeInteraction() {
        // Cancel all timers
        for timer in squarePipeTimers.values {
            timer.invalidate()
        }
        squarePipeTimers.removeAll()
        
        // Cancel green timers
        for timer in squarePipeGreenTimers.values {
            timer.invalidate()
        }
        squarePipeGreenTimers.removeAll()
        
        // Clear clickable pipes and reset colors (but not gray pipes)
        for pipe in clickableSquarePipes {
            resetPipeColor(pipe)
        }
        clickableSquarePipes.removeAll()
        
        // Clear clicked squares when rotation ends
        clickedSquares.removeAll()
        clickedSquarePipes.removeAll()
        
        // Clear starter cell tracking when rotation ends
        squaresWithStarterCells.removeAll()
        
        squarePipeStartTime = nil
    }
    
    // Activate an entire square (make all pipes clickable and green)
    private func activateSquare(_ square: [CellPosition]) {
        // Only activate if still rotating
        guard isRotating else { return }
        
        // Check if this square contains any starter cells - if so, skip activation
        for pipe in square {
            let cellKey = "\(pipe.row)_\(pipe.col)"
            if squaresWithStarterCells.contains(cellKey) {
                return // Skip this square - it contains a starter cell
            }
        }
        
        // Add all pipes in the square to clickable set
        for pipe in square {
            clickableSquarePipes.insert(pipe)
            turnPipeGreen(pipe)
        }
        
        // Schedule deactivation of entire square after 3 seconds
        let greenTimer = Timer.scheduledTimer(withTimeInterval: SQAURE_CLICK_TIMEOUT, repeats: false) { [weak self] _ in
            self?.deactivateSquare(square)
        }
        
        // Store timer with a unique key for the square
        let squareKey = "square_\(square[0].row)_\(square[0].col)"
        squarePipeGreenTimers[squareKey] = greenTimer
    }
    
    // Deactivate an entire square (remove all pipes from clickable and reset colors)
    private func deactivateSquare(_ square: [CellPosition]) {
        for pipe in square {
            clickableSquarePipes.remove(pipe)
            
            // Check if this pipe was clicked
            let wasClicked = clickedSquarePipes.contains(pipe)
            
            if wasClicked {
                // Square was clicked, reset to original color
                resetPipeColor(pipe)
            } else {
                // Square expired without being clicked, turn gray
                turnPipeGray(pipe)
                expiredSquares.insert(pipe)
            }
        }
        
        // Remove the timer
        let squareKey = "square_\(square[0].row)_\(square[0].col)"
        squarePipeGreenTimers.removeValue(forKey: squareKey)
    }
    
    // Turn a pipe green to indicate it's clickable
    private func turnPipeGreen(_ pipe: CellPosition) {
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = UIColor.systemGreen
        }
    }
    
    // Turn a pipe gray to indicate it's expired
    private func turnPipeGray(_ pipe: CellPosition) {
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = UIColor.gray
        }
    }
    
    // Highlight a pipe as rotating (pink color)
    private func highlightRotatingPipe(_ pipe: CellPosition) {
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            // Store original material only if we haven't stored it yet in this rotation cycle
            if originalMaterials[cylinderNode] == nil {
                // Store the true original color (blue) regardless of current color
                let originalMaterial = material.copy() as? SCNMaterial
                originalMaterial?.diffuse.contents = UIColor.systemBlue
                originalMaterials[cylinderNode] = originalMaterial
            }
            material.diffuse.contents = UIColor.systemPink
        }
    }
    
    // Reset a pipe's color to its original state
    private func resetPipeColor(_ pipe: CellPosition) {
        // Don't reset gray pipes unless the board is being reset
        if expiredSquares.contains(pipe) {
            return
        }
        
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            // Check if this pipe was in the original materials (pink during rotation)
            if let originalMaterial = originalMaterials[cylinderNode] {
                material.diffuse.contents = originalMaterial.diffuse.contents
            } else {
                // Reset to default blue
                material.diffuse.contents = UIColor.systemBlue
            }
        }
    }
    
    // Handle click on a square pipe during rotation
    private func handleSquarePipeClick(_ pipe: CellPosition) {
        // Add bonus points for clicking square pipes
        addToScore(5)
        
        // Find which square this pipe belongs to and deactivate the entire square
        for square in pipeSquares {
            if square.contains(pipe) {
                // Mark all pipes in this square as clicked
                for squarePipe in square {
                    clickedSquarePipes.insert(squarePipe)
                }
                
                deactivateSquare(square)
                
                // Add this square to the clicked squares list for next rotation
                if !clickedSquares.contains(square) {
                    clickedSquares.append(square)
                }
                
                // Show congratulations banner
                showCongratulationsBanner()
                break
            }
        }
    }
    
    // Process clicked squares and add their cells to rotation with target rotations
    private func processClickedSquares() -> [[CellPosition]] {
        var squaresToRotate: [[CellPosition]] = []
        
        for square in clickedSquares {
            // Add all cells in the square to rotation
            squaresToRotate.append(square)
        }
        
        // Clear the clicked squares list
        clickedSquares.removeAll()
        
        return squaresToRotate
    }
    
    // Reset an expired pipe's color to blue (used during board reset)
    private func resetExpiredPipeColor(_ pipe: CellPosition) {
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = UIColor.systemBlue
        }
    }
    
    // Show congratulations banner when a square is broken
    private func showCongratulationsBanner() {
        // Remove any existing banner
        congratulationsBanner?.removeFromSuperview()
        
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
        label.text = "Squarebreaker! 🎉"
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.textColor = UIColor.black
        label.textAlignment = .center
        
        // Add label to banner
        banner.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add banner to view
        view.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup constraints
        NSLayoutConstraint.activate([
            // Banner constraints
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 20),
            banner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            banner.heightAnchor.constraint(equalToConstant: 50),
            
            // Label constraints
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -10)
        ])
        
        // Store reference
        congratulationsBanner = banner
        
        // Animate in
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 50)
        
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [], animations: {
            banner.alpha = 1
            banner.transform = .identity
        })
        
        // Animate out after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UIView.animate(withDuration: 0.3, animations: {
                banner.alpha = 0
                banner.transform = CGAffineTransform(translationX: 0, y: -30)
            }, completion: { _ in
                banner.removeFromSuperview()
                self.congratulationsBanner = nil
            })
        }
    }
    
    // Track squares that contain starter cells (cells that initiated this rotation)
    private func trackSquaresWithStarterCells(_ cells: [CellPosition]) {
        squaresWithStarterCells.removeAll()
        for cell in cells {
            let cellKey = "\(cell.row)_\(cell.col)"
            squaresWithStarterCells.insert(cellKey)
        }
    }
}

// MARK: - CAAnimationDelegate
extension GameViewController: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag {
            // Check if this animation has a completion callback
            if let completion = anim.value(forKey: "completionCallback") as? () -> Void {
                completion()
            }
        }
    }
}
