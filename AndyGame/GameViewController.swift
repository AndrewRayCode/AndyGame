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

/**

TODO
- Squareformer needs to pause, so does flower breaker
- Squareformer still causes all pipes to turn blue
- Try particle effect
- Flower needs to reset to previous rotations after it's formed if user doesn't click
- Flower breaking open should turn the flower cells one color and the corners another (or maybe keep blue)
- make flower appear in random position, not always first open space

Non-interactive Bonus elements
- Square formation (and then it auto breaks) bonus
- Island bonus?
- All cells rotated in one game bonus?
- All cells rotated in one *move* bonus?
- Move that goes over 5-10 etc rotations?
- Move counter limit

Interactive elements:
- Square breaker
- Last chance (and follow-ups?)
- Multiple board sizes?
- Bonus if every cell on the board has rotated
 */
class GameViewController: UIViewController {
    
    // Grid dimensions
    // vertical axis
    private let GRID_ROWS = 12
    // horizontal axis
    private let GRID_COLS = 10
    private let GRID_SPACING = 1.1
    
    private let GRID_PADDING: Float = 1.0 // Padding around the grid in world units
    
    private let CAMERA_DISTANCE: Float = 10.0
    
    private let ROTATION_TIME = 0.6
    
    private let CYLINDER_RADIUS: Float = 0.5
    private let CYLINDER_HEIGHT: Float = 0.5

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

    private let CYLINDER_COLOR = UIColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 1.0)

    private let CYLINDER_HAS_ROTATED_COLOR = UIColor(red: 0.1, green: 0.5, blue: 1.0, alpha: 1.0)
    private let CYLINDER_COLOR_HIGHLIGHT = UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1.0)

    private let SQUARE_HIGHLIGHT_COLOR = UIColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1.0)
    private let SQUARE_DISABLED_COLOR = UIColor(red: 0.5, green: 0.5, blue: 0.7, alpha: 1.0)

    private let SQUARE_CLICK_MIN_WAIT = 1.0
    private let SQUARE_CLICK_MAX_WAIT = 2.0
    private let SQAURE_CLICK_TIMEOUT = 5.0
    
    private let LAST_CHANCE_TIME = 5.0
    private let ROTATION_DURATION = 0.3
    private let FLOWER_CLICK_MAX_WAIT = 3.0
    
    // Pause for effect in (at least) square breaker
    private let ROTATION_COMPLETION_DELAY = 0.5
    
    // Track clicked squares for next rotation
    private var clickedSquares: [[CellPosition]] = []
    
    // Track expired squares (squares that weren't clicked in time)
    private var expiredSquares: Set<CellPosition> = []
    
    // Track squares that were clicked (to prevent them from turning gray)
    private var clickedSquarePipes: Set<CellPosition> = []
    
    // Track squares that contain cells used as rotation starters (to prevent them from becoming clickable)
    private var squaresWithStarterCells: Set<String> = []
    
    // Last chance mechanic tracking
    private var lastChanceCell: CellPosition?
    private var lastChanceTimer: Timer?
    
    // Square breaking delay tracking
    private var shouldDelayNextRotation = false
    
    // Track previous pipe squares for new square detection
    private var previousPipeSquares: [[CellPosition]] = []
    
    // Track newly formed squares that need to be broken open
    private var newlyFormedSquares: [[CellPosition]] = []
    
    // Flower pattern tracking
    private var flowerFormationTimer: Timer?
    
    // Flower interaction tracking
    private var activeFlower: (area: (startRow: Int, startCol: Int), previousRotations: [[Int]], timer: Timer)?
    private var clickableFlowerCells: Set<CellPosition> = []
    private var flowerCellsToRotate: [CellPosition] = []
    
    // Track formations created in current rotation frame
    private var squaresCreatedThisFrame: Set<CellPosition> = []
    private var flowersCreatedThisFrame: Set<CellPosition> = []
    
    // Flower rotation pattern (4x4 grid)
    private let flowerPattern: [[Int?]] = [
        [nil, 1, 2, nil],      // [don't rotate, .one, .two, don't rotate]
        [1, 3, 0, 2],          // [.one, .three, .zero, .two]
        [0, 2, 1, 3],          // [.zero, .two, .one, .three]
        [nil, 0, 3, nil]       // [don't rotate, .zero, .three, don't rotate]
    ]
    
    // Particle system for square breaking effects
    private var squareBreakParticleSystem: SCNParticleSystem?
    
    // Banner manager
    private var bannerManager: BannerManager!
    
    // Reset button
    private var resetButton: UIButton!
    
    // Flower test button
    private var flowerTestButton: UIButton!
    
    // Camera node reference
    private var cameraNode: SCNNode!
    
    // Score tracking
    private var currentScore: Int = 0
    private var highScore: Int = 0
    
    // Move tracking
    private let maxMovesPerGame: Int = 5
    private var remainingMoves: Int = 0
    
    // Score display labels
    private var currentScoreLabel: UILabel!
    private var highScoreLabel: UILabel!
    
    // Move counter label
    private var movesLabel: UILabel!
    
    var scene: SCNScene!
    var gridGroupNode: SCNNode!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize rotation states array
        rotationStates = Array(repeating: Array(repeating: 0, count: GRID_COLS), count: GRID_ROWS)
        
        // create a new scene
        scene = SCNScene()
        
        // Setup particle system for square breaking
        setupSquareBreakParticleSystem()
        
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
        cameraNode.position = SCNVector3(x: 0, y: CAMERA_DISTANCE, z: -0.5)
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
                let cylinderGeometry = SCNCylinder(radius: CGFloat(CYLINDER_RADIUS), height: CGFloat(CYLINDER_HEIGHT))
                
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
                    y: CYLINDER_HEIGHT / 2, // Place on ground level
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
                    y: CYLINDER_HEIGHT / 2,
                    z: 0
                )
                let childPipeScale = Float(0.25)
                childPipe.scale = SCNVector3(x: childPipeScale, y: childPipeScale, z: childPipeScale)
                childPipe.eulerAngles = SCNVector3(x: Float.pi / 2, y: 0, z: 0)
                cylinderNode.addChildNode(childPipe)
            }
        }

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
        
        // Initialize moves display
        updateMovesDisplay()
        
        // Initialize banner manager
        bannerManager = BannerManager(parentView: view)
        
        // Initialize previous pipe squares for new square detection
        previousPipeSquares = []
        
        // Randomize the initial board state
        resetBoard()
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
            
            // Check if this is a last chance cell click
            if let lastChanceCell = lastChanceCell, position == lastChanceCell {
                // Handle last chance cell click
                handleLastChanceClick(position)
                return
            }
            
            // User clicked the flower in time!
            if clickableFlowerCells.contains(position) {
                shouldDelayNextRotation = true
                
                bannerManager.showBanner(message: "Flower breaker!")

                // Pop the flower open with the specified pattern
                popFlowerOpen(area: activeFlower!.area)

                // Clear the active flower
                clearActiveFlower()
                
                return
            }
            
            // Normal pipe click - only allow if not rotating and has moves remaining
            if isRotating || remainingMoves <= 0 {
                return
            }
            
            // If there's an active last chance timer, clear it and start new rotation
            if lastChanceTimer != nil {
                clearLastChance()
            }
            
            // Decrement remaining moves
            remainingMoves -= 1
            updateMovesDisplay()

            // Rotate the clicked cell
            rotateCells([position], [])
        }
    }

    // On initial tap, this rotates the first cell.
    // On subsequent rotation completions, this function is called with the
    // *finished* rotations   
    private func rotateCells(_ cells: [CellPosition], _ squareCellsToExpand: [[CellPosition]] = []) {
        // Set rotating flag to prevent other taps
        isRotating = true
        updateResetButtonState()
        
        // Clear frame tracking for new rotation
        squaresCreatedThisFrame.removeAll()
        flowersCreatedThisFrame.removeAll()
        
        detectPipeSquares()
        
        // Track squares that contain starter cells (cells that initiated this rotation)
        trackSquaresWithStarterCells(cells)
        
        // Start square pipe interaction system only if not already started
        if squarePipeStartTime == nil {
            startSquarePipeInteraction()
        }
        
        // 1 in 10 chance to trigger flower formation
        if Int.random(in: 1...10) == 1 {
            triggerFlowerFormation()
        }
        
        // Pop open the square
        for square in squareCellsToExpand {
            let topRight = square[1]
            let bottomLeft = square[2]
            let bottomRight = square[3]
            let topLeft = square[0]
            
            // Highlight all pipes in the square as rotating (red for clicked squares)
            highlightRotatingPipe(topLeft)
            highlightRotatingPipe(topRight)
            highlightRotatingPipe(bottomLeft)
            highlightRotatingPipe(bottomRight)
            
            rotationStates[topLeft.row][topLeft.col] += 2
            rotationStates[topRight.row][topRight.col] += 2
            rotationStates[bottomLeft.row][bottomLeft.col] += 2
            rotationStates[bottomRight.row][bottomRight.col] += 2
            
            animatePipeRotation(cell: topLeft, targetRotation: rotationStates[topLeft.row][topLeft.col])
            animatePipeRotation(cell: topRight, targetRotation: rotationStates[topRight.row][topRight.col])
            animatePipeRotation(cell: bottomLeft, targetRotation: rotationStates[bottomLeft.row][bottomLeft.col])
            animatePipeRotation(cell: bottomRight, targetRotation: rotationStates[bottomRight.row][bottomRight.col])
        }
        
        // Remove cells that are part of squareCellsToExpand from the cells array
        let cellsInSquares = squareCellsToExpand.flatMap { $0 }
        let squareCells = Set(cellsInSquares)
        let filteredCells = cells.filter { !squareCells.contains($0) }
        
        // Edge case: When all rotating cells are part of squares, the square
        // has popped open, but there will be nothing left in cells to animate.
        // So manually fire the next step
        if filteredCells.count == 0 && squareCells.count > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + ROTATION_TIME) {
                self.onRotationComplete(rotatedCells: cellsInSquares)
            }
        } else {
            animationCompletionCount = 0
            totalAnimationsInBatch = filteredCells.count
            currentRotatingCells = cells
            
            // Process each cell in the filtered array
            // get cell and for loop index
            for cell in filteredCells {
                // Update rotation state (unbounded)
                rotationStates[cell.row][cell.col] -= 1
                
                // Add 1 point for each rotation
                addToScore(1)
                
                // Calculate visual rotation based on state
                let rotationState = rotationStates[cell.row][cell.col]
                
                // Highlight the pipe as rotating
                highlightRotatingPipe(cell)
                animatePipeRotation(cell: cell, targetRotation: rotationState)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + ROTATION_TIME) {
                let cellsAndCellsInSquares = cells + squareCellsToExpand.flatMap { $0 }
                self.onRotationComplete(rotatedCells: cellsAndCellsInSquares)
            }
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
        // Detect pipe squares after rotation
        detectPipeSquares()
        
        // Detect newly formed squares
        detectNewlyFormedSquares()
        
        var newNeighborsToRotate: [CellPosition] = []
        // Find connected neighbors for each rotated cell
        for cell in rotatedCells {
            let neighbors = findConnectedNeighbors(row: cell.row, col: cell.col)

            if neighbors.count > 0 {
                newNeighborsToRotate.append(cell)
                newNeighborsToRotate.append(contentsOf: neighbors)
            }
        }
        
        // Process clicked squares and add their cells to rotation with target rotations
        let clickedSquareCells = processClickedSquares()
        
        // Process newly formed squares and add their cells to rotation with target rotations
        let newlyFormedSquareCells = processNewlyFormedSquares()
        
        // Process flower cells that need to be rotated
        let flowerCellsForRotation = flowerCellsToRotate
        flowerCellsToRotate.removeAll() // Clear for next time
        
        // Deduplicate newNeighborsToRotate efficiently using a Set
        let uniqueNeighbors = Array(Set(newNeighborsToRotate))
        
        let allCellsToRotate = uniqueNeighbors + flowerCellsForRotation
        
        if allCellsToRotate.count > 0 {
            addToScore(allCellsToRotate.count)
            
            // Check if we should delay the next rotation
            if shouldDelayNextRotation {
                shouldDelayNextRotation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + ROTATION_COMPLETION_DELAY) {
                    self.rotateCells(allCellsToRotate, clickedSquareCells + newlyFormedSquareCells)
                }
            } else {
                // Restore all original materials when rotation chain is completely finished
                restoreOriginalMaterialsWithAnimation()
                rotateCells(allCellsToRotate, clickedSquareCells + newlyFormedSquareCells)
            }
        } else {
            restoreOriginalMaterialsWithAnimation()
            isRotating = false
            originalMaterials.removeAll()
            updateResetButtonState()
            
            // Stop square pipe interaction when rotation ends
            stopSquarePipeInteraction()
            
            // Clear any remaining flower cells that need rotation
            flowerCellsToRotate.removeAll()
            
            // Clear frame tracking
            squaresCreatedThisFrame.removeAll()
            flowersCreatedThisFrame.removeAll()
            
            // Reset any clickable flowers when rotations have stopped
            if activeFlower != nil {
                clearActiveFlower()
            }
            
            // Chance to trigger last chance mechanic
            if Int.random(in: 1...10) > 8 && remainingMoves < 4 {
                triggerLastChance()
            }
        }
    }
    
    private func setupResetButton() {
        resetButton = UIButton(type: .system)
        resetButton.setTitle("New Game", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = UIColor.systemBlue
        resetButton.layer.cornerRadius = 8
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        resetButton.addTarget(self, action: #selector(resetBoard), for: .touchUpInside)
        
        // Create flower test button
        flowerTestButton = UIButton(type: .system)
        flowerTestButton.setTitle("Flower Test", for: .normal)
        flowerTestButton.setTitleColor(.white, for: .normal)
        flowerTestButton.backgroundColor = UIColor.systemPurple
        flowerTestButton.layer.cornerRadius = 8
        flowerTestButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        flowerTestButton.addTarget(self, action: #selector(testFlowerFormation), for: .touchUpInside)
        
        // Add buttons to view
        view.addSubview(resetButton)
        view.addSubview(flowerTestButton)
        
        // Setup constraints
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        flowerTestButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Reset button
            resetButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resetButton.widthAnchor.constraint(equalToConstant: 120),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Flower test button
            flowerTestButton.topAnchor.constraint(equalTo: resetButton.bottomAnchor, constant: 10),
            flowerTestButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            flowerTestButton.widthAnchor.constraint(equalToConstant: 120),
            flowerTestButton.heightAnchor.constraint(equalToConstant: 44)
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
        
        // Reset move counter
        remainingMoves = maxMovesPerGame
        updateMovesDisplay()
        
        // Clear expired squares and reset their colors
        for pipe in expiredSquares {
            resetExpiredPipeColor(pipe)
        }
        expiredSquares.removeAll()
        clickedSquarePipes.removeAll()
        
        // Create array of all cells in diagonal order (top-left to bottom-right)
        var diagonalCells: [CellPosition] = []
        for sum in 0..<(GRID_ROWS + GRID_COLS - 1) {
            for row in 0..<GRID_ROWS {
                let col = sum - row
                if col >= 0 && col < GRID_COLS {
                    diagonalCells.append(CellPosition(row: row, col: col))
                }
            }
        }
        
        // Track completion of all reset animations
        var completedAnimations = 0
        let totalAnimations = diagonalCells.count
        let animationStagger = 0.007
        
        // Animate reset with staggered timing
        for (index, cell) in diagonalCells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * animationStagger + animationStagger) {
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
        
        // Clear starter cell tracking when rotation ends
        squaresWithStarterCells.removeAll()
        
        // Clear any active last chance timer
        lastChanceTimer?.invalidate()
        lastChanceTimer = nil
        lastChanceCell = nil
        
        // Clear any active flower
        clearActiveFlower()
        
        // Clear any flower cells that need rotation
        flowerCellsToRotate.removeAll()
        
        resetCurrentScore()
    }

    @objc private func testFlowerFormation() {
        guard !isRotating else { return }
        
        // Manually trigger flower formation for testing
        triggerFlowerFormation()
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
    
    // Used by resetBoard()
    private func animateSingleCellReset(cell: CellPosition, completion: @escaping () -> Void) {
        // Find the cylinder node for this position
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { 
            completion()
            return 
        }
        
        // Highlight cell during reset
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = CYLINDER_COLOR_HIGHLIGHT
        }
        
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
        
        let visualRotation = Float(rotation) * -Float.pi / 2
        
        let IN_ANIMATION_TIME = 0.25
        let OUT_ANIMATION_TIME = 0.25
        
        // Use springy animation for reset as well
        SCNTransaction.begin()
        SCNTransaction.animationDuration = IN_ANIMATION_TIME
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        // Animate both rotation and y position
        cylinderNode.eulerAngles.y = visualRotation
        cylinderNode.position.y = CYLINDER_HEIGHT / 2 + CYLINDER_HEIGHT * 2.0
        
        SCNTransaction.commit()
        
        // Use a timer to ensure the highlighting lasts for the full duration
        DispatchQueue.main.asyncAfter(deadline: .now() + IN_ANIMATION_TIME) {
            // Reset to normal blue and position after the full duration
            self.animateColorChange(for: cell, to: self.CYLINDER_COLOR, duration: OUT_ANIMATION_TIME)
            
            // Animate back to original position
            SCNTransaction.begin()
            SCNTransaction.animationDuration = OUT_ANIMATION_TIME
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cylinderNode.position.y = self.CYLINDER_HEIGHT / 2
            SCNTransaction.commit()
            
            completion()
        }
    }

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
        
        // Create high score container view
        let highScoreContainer = UIView()
        highScoreContainer.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        highScoreContainer.layer.cornerRadius = 8
        highScoreContainer.layer.masksToBounds = true
        
        // Create high score text label
        let highScoreTextLabel = UILabel()
        highScoreTextLabel.text = "High Score"
        highScoreTextLabel.textColor = .white
        highScoreTextLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        highScoreTextLabel.textAlignment = .center
        
        // Create high score number label
        highScoreLabel = UILabel()
        highScoreLabel.text = "0"
        highScoreLabel.textColor = UIColor.systemYellow
        highScoreLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        highScoreLabel.textAlignment = .center
        
        // Add labels to container
        highScoreContainer.addSubview(highScoreTextLabel)
        highScoreContainer.addSubview(highScoreLabel)
        
        // Create moves label
        movesLabel = UILabel()
        movesLabel.text = "Moves: 10"
        movesLabel.textColor = .white
        movesLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        movesLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        movesLabel.layer.cornerRadius = 8
        movesLabel.layer.masksToBounds = true
        movesLabel.textAlignment = .center
        
        view.addSubview(currentScoreLabel)
        view.addSubview(highScoreContainer)
        view.addSubview(movesLabel)
        
        // Setup constraints
        currentScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        highScoreContainer.translatesAutoresizingMaskIntoConstraints = false
        highScoreTextLabel.translatesAutoresizingMaskIntoConstraints = false
        highScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        movesLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Current score label
            currentScoreLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            currentScoreLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            currentScoreLabel.widthAnchor.constraint(equalToConstant: 120),
            currentScoreLabel.heightAnchor.constraint(equalToConstant: 30),
            
            // High score container
            highScoreContainer.topAnchor.constraint(equalTo: currentScoreLabel.bottomAnchor, constant: 8),
            highScoreContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            highScoreContainer.widthAnchor.constraint(equalToConstant: 120),
            highScoreContainer.heightAnchor.constraint(equalToConstant: 50),
            
            // Moves label
            movesLabel.topAnchor.constraint(equalTo: highScoreContainer.bottomAnchor, constant: 8),
            movesLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            movesLabel.widthAnchor.constraint(equalToConstant: 120),
            movesLabel.heightAnchor.constraint(equalToConstant: 30),
            
            // High score text label
            highScoreTextLabel.topAnchor.constraint(equalTo: highScoreContainer.topAnchor, constant: 5),
            highScoreTextLabel.leadingAnchor.constraint(equalTo: highScoreContainer.leadingAnchor, constant: 5),
            highScoreTextLabel.trailingAnchor.constraint(equalTo: highScoreContainer.trailingAnchor, constant: -5),
            highScoreTextLabel.heightAnchor.constraint(equalToConstant: 20),
            
            // High score number label
            highScoreLabel.topAnchor.constraint(equalTo: highScoreTextLabel.bottomAnchor, constant: 2),
            highScoreLabel.leadingAnchor.constraint(equalTo: highScoreContainer.leadingAnchor, constant: 5),
            highScoreLabel.trailingAnchor.constraint(equalTo: highScoreContainer.trailingAnchor, constant: -5),
            highScoreLabel.bottomAnchor.constraint(equalTo: highScoreContainer.bottomAnchor, constant: -5)
        ])
        
        updateScoreDisplay()
    }
    
    private func updateScoreDisplay() {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        
        if let formattedCurrentScore = numberFormatter.string(from: NSNumber(value: currentScore)) {
            currentScoreLabel.text = "Score: \(formattedCurrentScore)"
        } else {
            currentScoreLabel.text = "Score: \(currentScore)"
        }
        
        if let formattedHighScore = numberFormatter.string(from: NSNumber(value: highScore)) {
            highScoreLabel.text = "\(formattedHighScore)"
        } else {
            highScoreLabel.text = "\(highScore)"
        }
    }
    
    private func updateMovesDisplay() {
        guard let movesLabel = movesLabel else { return }
        
        if remainingMoves > 1 {
            movesLabel.text = "Moves: \(remainingMoves)"
            movesLabel.textColor = .white
        } else if remainingMoves == 1 {
            movesLabel.text = "Last move!"
            movesLabel.textColor = UIColor.systemYellow
        } else {
            movesLabel.text = "No moves remaining"
            movesLabel.textColor = UIColor.systemRed
        }
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
        })
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
        squaresCreatedThisFrame.removeAll() // Clear tracking for this frame
        
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
                    
                    // Check for overlap with flowers created this frame
                    let hasFlowerOverlap = squareCells.contains { cell in
                        flowersCreatedThisFrame.contains(cell)
                    }
                    
                    if !hasFlowerOverlap {
                        pipeSquares.append(squareCells)
                        // Track these cells as squares created this frame
                        for cell in squareCells {
                            squaresCreatedThisFrame.insert(cell)
                        }
                    }
                }
            }
        }
    }
    
    // Check if a 2x2 area forms the specific square pattern
    private func isSquarePattern(at row: Int, col: Int) -> Bool {
        // Check if any cell in this 2x2 area is part of an active flower
        let squareCells = [
            CellPosition(row: row, col: col),
            CellPosition(row: row, col: col + 1),
            CellPosition(row: row + 1, col: col),
            CellPosition(row: row + 1, col: col + 1)
        ]
        
        // If any cell is part of an active flower, don't form a square
        for cell in squareCells {
            if clickableFlowerCells.contains(cell) {
                return false
            }
        }
        
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
        
        // Clear newly formed squares when rotation ends
        newlyFormedSquares.removeAll()
        
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
        
        // Check if any pipes in this square are expired (gray) - if so, skip activation
        for pipe in square {
            if expiredSquares.contains(pipe) {
                return // Skip this square - it contains expired pipes
            }
        }
        
        // Add all pipes in the square to clickable set
        for pipe in square {
            clickableSquarePipes.insert(pipe)
            animateColorChange(for: pipe, to: SQUARE_HIGHLIGHT_COLOR, duration: 0.2)
            animateCellYPosition(for: pipe, towardCamera: true, duration: 0.3)
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
                // Square was clicked, keep it gold (color change already handled in handleSquarePipeClick)
                // Don't reset color here since we want it to stay gold
            } else {
                // Square expired without being clicked
                animateColorChange(for: pipe, to: SQUARE_DISABLED_COLOR, duration: 0.3)
                animateCellYPosition(for: pipe, towardCamera: false, duration: 0.3)
                expiredSquares.insert(pipe)
            }
        }
        
        // Remove the timer
        let squareKey = "square_\(square[0].row)_\(square[0].col)"
        squarePipeGreenTimers.removeValue(forKey: squareKey)
    }
    
    // Highlight a pipe as rotating (pink color)
    private func highlightRotatingPipe(_ pipe: CellPosition) {
        guard let cylinderNode = findCylinderNode(at: pipe.row, col: pipe.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            // Store original material only if we haven't stored it yet in this rotation cycle
            if originalMaterials[cylinderNode] == nil {
                // Store the true original color (blue) regardless of current color
                let originalMaterial = material.copy() as? SCNMaterial
                originalMaterial?.diffuse.contents = CYLINDER_COLOR
                originalMaterials[cylinderNode] = originalMaterial
            }
            // Use instant color change for rotation highlighting to prevent pulsing
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
        
        // Check if this pipe was in the original materials (pink during rotation)
        if let originalMaterial = originalMaterials[cylinderNode] {
            animateColorChange(for: pipe, to: originalMaterial.diffuse.contents as? UIColor ?? CYLINDER_COLOR, duration: 0.2)
        } else {
            // Reset to default blue
            animateColorChange(for: pipe, to: CYLINDER_COLOR, duration: 0.2)
        }
        
        // Animate back to original position
        animateCellYPosition(for: pipe, towardCamera: false, duration: 0.3)
    }
    
    // Handle click on a square pipe during rotation
    private func handleSquarePipeClick(_ pipe: CellPosition) {
        // Add bonus points for clicking square pipes
        addToScore(5)
        
        // Find which square this pipe belongs to and deactivate the entire square
        for square in pipeSquares {
            if square.contains(pipe) {
                // Trigger particle effect at the center of the square
                let centerPosition = getSquareCenterPosition(square)
                triggerSquareBreakParticles(at: centerPosition)
                
                // Mark all pipes in this square as clicked
                for squarePipe in square {
                    clickedSquarePipes.insert(squarePipe)
                }
                
                // Turn all pipes in the square gold as they sink back down
                for squarePipe in square {
                    animateColorChange(for: squarePipe, to: UIColor.systemYellow, duration: 0.3)
                    animateCellYPosition(for: squarePipe, towardCamera: false, duration: 0.3)
                }
                
                deactivateSquare(square)
                
                // Add this square to the clicked squares list for next rotation
                if !clickedSquares.contains(square) {
                    clickedSquares.append(square)
                }
                
                // Set delay flag for next rotation step
                shouldDelayNextRotation = true
                
                bannerManager.showCongratulationsBanner()
                break
            }
        }
    }
    
    // Get the center position of a square in world coordinates
    private func getSquareCenterPosition(_ square: [CellPosition]) -> SCNVector3 {
        guard square.count == 4 else { return SCNVector3Zero }
        
        // Calculate average position using actual cylinder node positions
        var totalX: Float = 0
        var totalY: Float = 0
        var totalZ: Float = 0
        var validPositions = 0
        
        for cell in square {
            if let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) {
                let worldPosition = cylinderNode.worldPosition
                totalX += worldPosition.x
                totalY += worldPosition.y
                totalZ += worldPosition.z
                validPositions += 1
            }
        }
        
        guard validPositions > 0 else { 
            print("No valid cylinder nodes found for square")
            return SCNVector3Zero 
        }
        
        let centerX = totalX / Float(validPositions)
        let centerY = totalY / Float(validPositions) + 1.0 // Position above the pipes
        let centerZ = totalZ / Float(validPositions)
        
        let finalPosition = SCNVector3(centerX, centerY, centerZ)
        print("Square center calculated at: \(finalPosition)")
        return finalPosition
    }
    
    // Handle click on last chance cell
    private func handleLastChanceClick(_ cell: CellPosition) {
        // Clear the last chance timer and highlight
        clearLastChance()
        
        // Add bonus points
        addToScore(10)
        
        // Check if user has no moves left and give them one more
        if remainingMoves <= 0 {
            remainingMoves = 1
            updateMovesDisplay()
            bannerManager.showBanner(message: "One more move! 🎯")
        } else {
            bannerManager.showBanner(message: "Randomize! +10 points! 🎯")
        }
        
        // Trigger radius randomization around the clicked cell
        randomizeRadiusAroundCell(cell)
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
    
    // Process newly formed squares and add their cells to rotation with target rotations
    private func processNewlyFormedSquares() -> [[CellPosition]] {
        var squaresToRotate: [[CellPosition]] = []
        
        for square in newlyFormedSquares {
            // Add all cells in the square to rotation
            squaresToRotate.append(square)
        }
        
        // Clear the newly formed squares list
        newlyFormedSquares.removeAll()
        
        return squaresToRotate
    }
    
    // Reset an expired pipe's color to blue (used during board reset)
    private func resetExpiredPipeColor(_ pipe: CellPosition) {
        animateColorChange(for: pipe, to: CYLINDER_COLOR, duration: 0.3)
    }
    
    // Track squares that contain starter cells (cells that initiated this rotation)
    private func trackSquaresWithStarterCells(_ cells: [CellPosition]) {
        squaresWithStarterCells.removeAll()
        for cell in cells {
            let cellKey = "\(cell.row)_\(cell.col)"
            squaresWithStarterCells.insert(cellKey)
        }
    }
    
    // Trigger last chance mechanic
    private func triggerLastChance() {
        // Select a random cell on the board
        let randomRow = Int.random(in: 1..<GRID_ROWS-1)
        let randomCol = Int.random(in: 1..<GRID_COLS-1)
        let randomCell = CellPosition(row: randomRow, col: randomCol)
        
        // Store the last chance cell
        lastChanceCell = randomCell
        
        // Highlight the cell (use a distinct color like orange)
        highlightLastChanceCell(randomCell)
        
        // Set up timer to clear the highlight after LAST_CHANCE_TIME seconds
        lastChanceTimer = Timer.scheduledTimer(withTimeInterval: LAST_CHANCE_TIME, repeats: false) { [weak self] _ in
            self?.clearLastChance()
        }
    }
    
    // Highlight a cell for last chance mechanic
    private func highlightLastChanceCell(_ cell: CellPosition) {
        animateColorChange(for: cell, to: UIColor.systemOrange, duration: 0.3)
        animateCellYPosition(for: cell, towardCamera: true, duration: 0.3)
    }
    
    // Clear last chance highlight
    private func clearLastChance() {
        guard let cell = lastChanceCell else { return }
        
        // Reset the cell color
        resetPipeColor(cell)
        
        // Animate back to original position
        animateCellYPosition(for: cell, towardCamera: false, duration: 0.3)
        
        // Clear tracking
        lastChanceCell = nil
        lastChanceTimer = nil
    }
    
    // Randomize cells in a radius around a given cell
    private func randomizeRadiusAroundCell(_ centerCell: CellPosition) {
        // Calculate radius of board size. This needs to be configurable
        let radius = max(1, Int(Double(min(GRID_ROWS, GRID_COLS)) * 0.75))
        
        // Collect all cells within the radius
        var cellsInRadius: [CellPosition] = []
        
        for row in 0..<GRID_ROWS {
            for col in 0..<GRID_COLS {
                let distance = abs(row - centerCell.row) + abs(col - centerCell.col) // Manhattan distance
                if distance <= radius {
                    cellsInRadius.append(CellPosition(row: row, col: col))
                }
            }
        }
        
        // Sort cells in diagonal pattern (similar to resetBoard)
        let sortedCells = cellsInRadius.sorted { cell1, cell2 in
            let sum1 = cell1.row + cell1.col
            let sum2 = cell2.row + cell2.col
            if sum1 != sum2 {
                return sum1 < sum2
            }
            return cell1.row < cell2.row
        }
        
        // Disable board interactions during randomization
        isRotating = true
        updateResetButtonState()
        
        // Track completion of all radius animations
        var completedAnimations = 0
        let totalAnimations = sortedCells.count
        let animationStagger = 0.02 // Slightly faster than resetBoard
        
        // Animate radius randomization with staggered timing
        for (index, cell) in sortedCells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * animationStagger) {
                self.animateSingleCellRandomization(
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
    
    // Used by last chance
    private func animateSingleCellRandomization(cell: CellPosition, completion: @escaping () -> Void) {
        // Find the cylinder node for this position
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { 
            completion()
            return 
        }
        
        // Always highlight the cell white during randomization
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            material.diffuse.contents = CYLINDER_COLOR_HIGHLIGHT
        }
        
        // Randomize rotation state
        let randomState = Int.random(in: 0...3)
        rotationStates[cell.row][cell.col] += randomState
        
        let rotation = rotationStates[cell.row][cell.col]
        let visualRotation = Float(rotation) * -Float.pi / 2
        
        let ANIMATE_IN_DURATION = 0.25
        let ANIMATE_OUT_DURATION = 0.25
        
        // Use springy animation for randomization
        SCNTransaction.begin()
        SCNTransaction.animationDuration = ANIMATE_IN_DURATION
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        // Animate both rotation and y position
        cylinderNode.eulerAngles.y = visualRotation
        cylinderNode.position.y = CYLINDER_HEIGHT / 2 + CYLINDER_HEIGHT * 2.0
        
        SCNTransaction.commit()
        
        // Use a timer to ensure the white highlighting lasts for the full duration
        DispatchQueue.main.asyncAfter(deadline: .now() + ANIMATE_IN_DURATION) {
            // Reset to normal blue and position after the full duration
            self.animateColorChange(for: cell, to: self.CYLINDER_COLOR, duration: ANIMATE_OUT_DURATION)
            
            // Animate back to original position
            SCNTransaction.begin()
            SCNTransaction.animationDuration = ANIMATE_OUT_DURATION
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cylinderNode.position.y = self.CYLINDER_HEIGHT / 2
            SCNTransaction.commit()
            
            completion()
        }
    }

    // Animate color change for a pipe
    private func animateColorChange(for cell: CellPosition, to color: UIColor, duration: TimeInterval = 0.3) {
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { return }
        
        if let geometry = cylinderNode.geometry, let material = geometry.firstMaterial {
            // Skip animation if the color is already the target color
            if let currentColor = material.diffuse.contents as? UIColor, currentColor == color {
                return
            }
            
            // Use SCNTransaction for SceneKit material animations
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Animate the color change
            material.diffuse.contents = color
            
            SCNTransaction.commit()
        }
    }

    // Animate cell y position toward or away from camera
    private func animateCellYPosition(for cell: CellPosition, towardCamera: Bool, duration: TimeInterval = 0.3) {
        guard let cylinderNode = findCylinderNode(at: cell.row, col: cell.col) else { return }
        
        let targetY: Float = towardCamera ? CYLINDER_HEIGHT / 2 + CYLINDER_HEIGHT : CYLINDER_HEIGHT / 2
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        cylinderNode.position.y = targetY
        
        SCNTransaction.commit()
    }

    // Detect newly formed squares
    // HAS AN IMPLICIT DEPENDENCY ON detectPipeSquares()
    // The logic in this class is a mix of mutating global game state and
    // functions that return values!
    private func detectNewlyFormedSquares() {
        // Find squares that exist now but didn't exist before
        for newSquare in pipeSquares {
            let isNewSquare = !previousPipeSquares.contains { oldSquare in
                // Check if this square is the same as any previous square
                return newSquare.count == oldSquare.count && 
                       newSquare.allSatisfy { cell in oldSquare.contains(cell) }
            }
            
            if isNewSquare {
                // Check if any cells in this square were rotated in the current step
                let rotatedCellPositions = Set(currentRotatingCells)
                let squareCellPositions = Set(newSquare)
                let hasRotatedCells = !rotatedCellPositions.isDisjoint(with: squareCellPositions)
                
                if hasRotatedCells {
                    // Highlight the newly formed square in gold
                    for cell in newSquare {
                        animateColorChange(for: cell, to: UIColor.systemYellow, duration: 0.3)
                    }
                    
                    // Add to newly formed squares list for next rotation
                    newlyFormedSquares.append(newSquare)
                    
                    // Set delay flag for next rotation step
                    shouldDelayNextRotation = true
                    
                    bannerManager.showBanner(message: "Squareformer! 🔲")
                    break // Only process one new square per rotation
                }
            }
        }
        
        // Update previous squares for next comparison
        previousPipeSquares = pipeSquares
    }

    // Trigger flower formation in a random 4x4 area
    private func triggerFlowerFormation() {
        // Only allow one flower at a time
        guard activeFlower == nil else { return }
        
        // Find a 4x4 area that doesn't contain any rotating cells
        guard let flowerArea = findFree4x4Area() else { return }
        
        // Check for overlap with squares created this frame
        let flowerCells = getFlowerCells(for: flowerArea)
        let hasSquareOverlap = flowerCells.contains { cell in
            squaresCreatedThisFrame.contains(cell)
        }
        
        if hasSquareOverlap {
            return // Don't form flower if it overlaps with squares created this frame
        }
        
        // Store previous rotations for the flower area
        let previousRotations = getPreviousRotations(for: flowerArea)
        
        // Apply flower pattern to the 4x4 area
        applyFlowerPattern(to: flowerArea)
        
        // Track these cells as flowers created this frame
        for cell in flowerCells {
            flowersCreatedThisFrame.insert(cell)
        }
        
        // Make flower cells clickable and start timer
        activateFlowerInteraction(area: flowerArea, previousRotations: previousRotations)
    }
    
    // Find a 4x4 area that doesn't contain any rotating cells
    private func findFree4x4Area() -> (startRow: Int, startCol: Int)? {
        // Check each possible 4x4 area on the board
        for startRow in 0..<(GRID_ROWS - 3) {
            for startCol in 0..<(GRID_COLS - 3) {
                // Check if this 4x4 area is free of rotating cells
                let isFree = check4x4AreaFree(startRow: startRow, startCol: startCol)
                if isFree {
                    return (startRow, startCol)
                }
            }
        }
        return nil
    }
    
    // Check if a 4x4 area is free of rotating cells
    private func check4x4AreaFree(startRow: Int, startCol: Int) -> Bool {
        for row in startRow..<(startRow + 4) {
            for col in startCol..<(startCol + 4) {
                let cell = CellPosition(row: row, col: col)
                
                // Check if cell is rotating
                if currentRotatingCells.contains(cell) {
                    return false
                }
                
                // Check if cell is part of an active (green) square
                if clickableSquarePipes.contains(cell) {
                    return false
                }
                
                // Check if cell is part of a deactivated (gray) square
                if expiredSquares.contains(cell) {
                    return false
                }
                
                // Check if cell is part of an active flower
                if clickableFlowerCells.contains(cell) {
                    return false
                }
                
                // Check if cell is adjacent to any rotating cell (buffer zone)
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let adjacentRow = row + dy
                    let adjacentCol = col + dx
                    
                    // Check bounds
                    if adjacentRow >= 0 && adjacentRow < GRID_ROWS && 
                       adjacentCol >= 0 && adjacentCol < GRID_COLS {
                        let adjacentCell = CellPosition(row: adjacentRow, col: adjacentCol)
                        if currentRotatingCells.contains(adjacentCell) {
                            return false
                        }
                    }
                }
            }
        }
        return true
    }
    
    // Apply flower pattern to a 4x4 area
    private func applyFlowerPattern(to area: (startRow: Int, startCol: Int)) {
        for row in 0..<4 {
            for col in 0..<4 {
                if let rotationOffset = flowerPattern[row][col] {
                    let cellRow = area.startRow + row
                    let cellCol = area.startCol + col
                    let cell = CellPosition(row: cellRow, col: cellCol)
                    
                    // Get the current unbounded rotation state
                    let currentRotation = rotationStates[cellRow][cellCol]
                    
                    // Find the next closest multiple of the target rotation
                    let targetRotation = findNextClosestMultiple(currentUnbounded: currentRotation, targetBounded: rotationOffset)
                    
                    // Apply the target rotation
                    rotationStates[cellRow][cellCol] = targetRotation
                    
                    // Animate the rotation
                    animatePipeRotation(cell: cell, targetRotation: targetRotation)
                }
            }
        }
    }

    // Get previous rotations for a flower area
    private func getPreviousRotations(for area: (startRow: Int, startCol: Int)) -> [[Int]] {
        var rotations: [[Int]] = []
        for row in 0..<4 {
            var rowRotations: [Int] = []
            for col in 0..<4 {
                let cellRow = area.startRow + row
                let cellCol = area.startCol + col
                rowRotations.append(rotationStates[cellRow][cellCol])
            }
            rotations.append(rowRotations)
        }
        return rotations
    }
    
    // Activate flower interaction (make clickable and start timer)
    private func activateFlowerInteraction(area: (startRow: Int, startCol: Int), previousRotations: [[Int]]) {
        // Add all flower cells to clickable set
        for row in 0..<4 {
            for col in 0..<4 {
                // Skip the corners
                if (row == 0 && col == 0) || (row == 0 && col == 3) || (row == 3 && col == 0) || (row == 3 && col == 3) {
                    continue
                }
                let cellRow = area.startRow + row
                let cellCol = area.startCol + col
                let cell = CellPosition(row: cellRow, col: cellCol)
                clickableFlowerCells.insert(cell)
                
                // Highlight flower cells (use a distinct color like pink)
                //animateColorChange(for: cell, to: UIColor.systemPink, duration: 0.3)
                animateCellYPosition(for: cell, towardCamera: true, duration: 0.3)
            }
        }
        
        // Start timer for flower timeout
        let timer = Timer.scheduledTimer(withTimeInterval: FLOWER_CLICK_MAX_WAIT, repeats: false) { [weak self] _ in
            self?.handleFlowerTimeout(area: area)
        }
        
        // Store active flower
        activeFlower = (area: area, previousRotations: previousRotations, timer: timer)
    }
    
    // Handle flower timeout (user didn't click in time)
    private func handleFlowerTimeout(area: (startRow: Int, startCol: Int)) {
        // Reset cells back to their previous rotations
        if let activeFlower = activeFlower {
            resetFlowerToPreviousRotations(area: area, previousRotations: activeFlower.previousRotations)
        }
        
        // Clear active flower
        clearActiveFlower()
    }
    
    // Reset flower cells back to their previous rotations
    private func resetFlowerToPreviousRotations(area: (startRow: Int, startCol: Int), previousRotations: [[Int]]) {
        for row in 0..<4 {
            for col in 0..<4 {
                let cellRow = area.startRow + row
                let cellCol = area.startCol + col
                let cell = CellPosition(row: cellRow, col: cellCol)
                
                // Get the previous rotation for this cell
                let previousRotation = previousRotations[row][col]
                
                // Reset the rotation state to the previous value
                rotationStates[cellRow][cellCol] = previousRotation
                
                // Animate the rotation back to the previous state
                animatePipeRotation(cell: cell, targetRotation: previousRotation)
            }
        }
    }
    
    // Pop flower open with the specified pattern
    private func popFlowerOpen(area: (startRow: Int, startCol: Int)) {
        /**
         * Start:
         * .┌┐.
         * ┌┘└┐
         * └┐┌┘
         * .└┘.
         * Goal:
         * .└┘.
         * ┐┌┐┌
         * ┘└┘└
         * .┌┐.
         */
        
        for row in 0..<4 {
            for col in 0..<4 {
                // If the corners are ignored, the flower pop open does a lot
                // less So adding the conrers to the rotation seems better
                // if (row == 0 && col == 0) || (row == 0 && col == 3) || (row == 3 && col == 0) || (row == 3 && col == 3) {
                //     continue
                // }
                let cellRow = area.startRow + row
                let cellCol = area.startCol + col
                let cell = CellPosition(row: cellRow, col: cellCol)

                // If the cell isn't a corner, animate it to green
                if !(row == 0 && col == 0) && !(row == 0 && col == 3) && !(row == 3 && col == 0) && !(row == 3 && col == 3) {
                    animateColorChange(for: cell, to: UIColor.systemGreen, duration: 0.5)
                }
                
                // Set the rotation state directly (not add to it)
                rotationStates[cellRow][cellCol] += 2
                
                // Add to flower cells that need to be rotated in the next step
                flowerCellsToRotate.append(cell)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Animate the rotation
                    let targetRotation = self.rotationStates[cellRow][cellCol]
                    self.animatePipeRotation(cell: cell, targetRotation: targetRotation)
                }
            }
        }
    }
    
    // Clear active flower
    private func clearActiveFlower() {
        // Clear clickable cells
        for cell in clickableFlowerCells {
            animateCellYPosition(for: cell, towardCamera: false, duration: 0.3)
        }
        clickableFlowerCells.removeAll()
        
        // Invalidate timer
        activeFlower?.timer.invalidate()
        activeFlower = nil
    }
    
    // Get all cells in a flower area (including corners)
    private func getFlowerCells(for area: (startRow: Int, startCol: Int)) -> [CellPosition] {
        var cells: [CellPosition] = []
        for row in 0..<4 {
            for col in 0..<4 {
                let cellRow = area.startRow + row
                let cellCol = area.startCol + col
                cells.append(CellPosition(row: cellRow, col: cellCol))
            }
        }
        return cells
    }
    
    // Find the next closest multiple of target rotation from current unbounded rotation
    private func findNextClosestMultiple(currentUnbounded: Int, targetBounded: Int) -> Int {
        // Ensure target is in range 0-3
        let normalizedTarget = ((targetBounded % 4) + 4) % 4
        
        // Find the current rotation modulo 4
        let currentMod4 = ((currentUnbounded % 4) + 4) % 4
        
        // Calculate the difference to reach the target
        let diff = normalizedTarget - currentMod4
        
        // Handle wraparound cases
        let adjustedDiff: Int
        if diff > 2 {
            // Target is much higher, go negative
            adjustedDiff = diff - 4
        } else if diff < -2 {
            // Target is much lower, go positive
            adjustedDiff = diff + 4
        } else {
            // Use the direct difference
            adjustedDiff = diff
        }
        
        // Return the next closest multiple
        return currentUnbounded + adjustedDiff
    }

    // Restore all original materials with animation
    private func restoreOriginalMaterialsWithAnimation() {
        for (node, _) in originalMaterials {
            if let geometry = node.geometry, let material = geometry.firstMaterial {
                // Animate the color change back to original
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.3
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                material.diffuse.contents = CYLINDER_HAS_ROTATED_COLOR
                SCNTransaction.commit()
            }
        }
    }

    // Setup particle system for square breaking effects
    private func setupSquareBreakParticleSystem() {
        let particleSystem = SCNParticleSystem()
        
        // Particle appearance - make particles larger and more visible
        particleSystem.particleSize = 0.01
        particleSystem.particleColor = UIColor.systemYellow
        particleSystem.particleColorVariation = SCNVector4(0.3, 0.3, 0.0, 0.2)
        
        // Particle behavior
        particleSystem.particleLifeSpan = 2.0
        particleSystem.particleLifeSpanVariation = 0.5
        particleSystem.emissionDuration = 0.5
        particleSystem.spreadingAngle = 90.0  // Wider spread
        particleSystem.acceleration = SCNVector3(0, -1.0, 0) // Lighter gravity
        
        // Emission properties - use volume instead of surface
        particleSystem.birthRate = 100
        particleSystem.birthLocation = .volume
        particleSystem.birthDirection = .random
        
        // Size variation over time
        particleSystem.particleSizeVariation = 0.1
        
        // Store the particle system
        squareBreakParticleSystem = particleSystem
    }
    
    // Trigger particle effect at a specific position
    private func triggerSquareBreakParticles(at position: SCNVector3) {
        guard let particleSystem = squareBreakParticleSystem?.copy() as? SCNParticleSystem else { 
            print("Failed to copy particle system")
            return 
        }
        
        // Create a node to hold the particle system
        let particleNode = SCNNode()
        particleNode.position = position
        
        // Add the particle system to the node
        particleNode.addParticleSystem(particleSystem)
        
        // Add to scene
        scene.rootNode.addChildNode(particleNode)
        
        print("Particle effect triggered at position: \(position)")
        
        // Remove the particle node after the effect is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            particleNode.removeFromParentNode()
            print("Particle node removed")
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
