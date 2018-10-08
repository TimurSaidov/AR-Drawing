import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    let configuration = ARWorldTrackingConfiguration()
    
    var selectedNode: SCNNode?
//    var sizeObject: Size?
    var placedNodes = [SCNNode]() // Коллекция узлов размещенных пользователем объектов.
    var planeNodes = [SCNNode]() // Коллекция узлов визуализированных плоскостей.
    
    var showPlaneOverlay = false {
        didSet {
            for node in planeNodes {
                node.isHidden = !showPlaneOverlay // Если showPlaneOverlay = false, то плоскости не показываются.
            }
//            planeNodes.forEach { node in // Для лучшего распараллеливания.
//                node.isHidden = !showPlaneOverlay
//            }
        }
    }
    
    var lastObjectPlacedPoint: CGPoint?
    let touchDistanceThreshold: CGFloat = 75
    
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    var objectMode: ObjectPlacementMode = .freeform {
        didSet { // didSet вызывается после того, как поменяется objectMode.
            reloadConfiguration() // При изменении objectMode (в UISegmentedControl), обновляется конфигурация сессии, как и во viewWillAppear при каждом новом появлении контроллера ViewController.
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration() // При каждом появлении контроллера, проверяется какой objectMode, и устанавливается конфигурация.
    }
    
    // Распознование плоскостей происходит при любом выбранном сегменте UISegmentedControl. Распознование картинки происходит только при выборе сегмента .image.
    func reloadConfiguration() {
        configuration.planeDetection = [.horizontal, .vertical] 
        
        configuration.detectionImages = (objectMode == .image) ? ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) : nil
        
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // При изменении сегмента UISegmentedControl меняется конфигурация.
    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
        case 1:
            objectMode = .plane
        case 2:
            objectMode = .image
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self // Указывается, что ViewController является делегатом протокола OptionsViewControllerDelegate (optionsViewController.delegate = ViewController). А поскольку ViewController подписан на него, он может выполнять его методы (методы протокола определяются в VC). Методы этого делегата delegate вызываются и выполняются уже в Options VC при выборе switch option (self.delegate?.togglePlaneVisualization() -> т.е. если есть делегат, а он есть (optionsViewController.delegate = ViewController), то вызывается его метод togglePlaneVisualization(), метод ViewController'а, который как раз и является делегатом).
        }
    }
    
    // Метод, вызывающийся при нажатии пользователем на экран.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let node = selectedNode, let touch = touches.first else { return } // Если выбран объект в опциях, т.е. есть node со своей геометрией, то она записывается в selectedNode в методе objectSelected(node: SCNNode) протокола OptionsViewControllerDelegate, затем при tap'e selectedNode записывается в новую константу node, которая затем передается в функцию addNodeInFront для добавления объектов на сцену. Там она клонируется в локальную константу cloneNode и добавляется на сцену.
        
        switch objectMode {
        case .freeform:
            addNodeInFront(node)
        case .plane:
            let touchLocation = touch.location(in: sceneView) // Где пользователь нажал. Возвращается точка нажатия.
            addNodeToPlane(node, toPlaneUsingPoint: touchLocation)
        case .image:
            break
        }
    }
    
    // Метод, вызывающийся, когда пользователь проводит пальцем по экрану.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard objectMode == .plane, let node = selectedNode, let touch = touches.first, let lastTouchPoint = lastObjectPlacedPoint else { return }
        
        let newTouchLocation = touch.location(in: sceneView)
        let a = newTouchLocation.x - lastTouchPoint.x
        let b = newTouchLocation.y - lastTouchPoint.y
        let distance = sqrt(a * a + b * b)
        if distance > touchDistanceThreshold {
            addNodeToPlane(node, toPlaneUsingPoint: newTouchLocation)
        }
    }
    
    // Метод, вызывающийся, когда пользователь убрал палец с экрана.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        lastObjectPlacedPoint = nil // Сбрасывание последней точки пересечения tap'а пользователя с визуализированной плоскостью.
    }
    
    // Метод, добавляющий объект (node = selectedNode) перед камерой (case .freeform).
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        var translation = matrix_identity_float4x4 // Единичная матрица 4х4.
        translation.columns.3.z = -0.2
        
        node.simdTransform = matrix_multiply(currentFrame.camera.transform, translation) // Вне зависимости от того, где tap'пает пользователь, объект размещается на расстоянии 20 см по оси z по отношению к положению камере. Перемножение матриц.
        node.eulerAngles.z = 0
//        let rotation = simd_float4x4(SCNMatrix4MakeRotation(GLKMathDegreesToRadians(90), 0, 0, 1))
//        translation = matrix_multiply(translation, rotation)
//        node.simdTransform = matrix_multiply(currentFrame.camera.transform, translation)

        addNodeToScene(node) // Для создания нескольких объектов на сцене.
    }
    
    // Метод, добавляющий объект (node = selectedNode) на распознанную и визуализированную плоскость (.plane).
    func addNodeToPlane(_ node: SCNNode, toPlaneUsingPoint point: CGPoint) {
        let hitTestResult = sceneView.hitTest(point, types: [.existingPlaneUsingExtent]) // Попытка пересечения луча, начинающегося оттуда, где пользователь нажал на экран (точка на экране с 2 координатами), с существующей плоскостью (учитывая ее размеры), соответствующей этому месту нажатия. Для этого нужна визуализированная плоскость. То место, где они пересекутся, и будет результатом.
        if let match = hitTestResult.first { // В массиве hitTestResult один элемент (координаты одной точки пересечения), так как каждый новый tap идет присваивание новых координат пересечения в массив. Не .append, а присваивание =. А если луч пересекся с двумя существующими плоскостями (например, плоскости были параллельны, одна за другой), то .first - это ближайшая к камере точка пересечения.
            let position = match.worldTransform.columns.3 // Позиция (координаты) точки пересечения.
            node.position = SCNVector3(position.x, position.y, position.z)
            addNodeToScene(node)
            lastObjectPlacedPoint = point // Сохранение координат точки, в которую размещается объект на плоскости.
        }
    }
    
    // Для создания множества объектов на сцене. Создается локальная константа cloneNode cтолько раз, сколько tap'ов совершает пользователь (Эти локальные константы имеют разные ячейки памяти несмотря на одинаковое название -> они все добавляются под rootNode, не перезаписываются). Без этой функции node постоянно бы перезаписывалась под rootNode (объект появился, однако при следующем tap'e предыдущий объект удалился, так как шла перезапись node). В результате под rootNode была бы одна node, меняющаяся при каждом tap'е.
    func addNodeToScene(_ node: SCNNode) {
        let cloneNode = node.clone()
        sceneView.scene.rootNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode) // Добавление в коллекцию узла объекта при tap'e пользователя.
    }
    
    // Вызывается при добавлении якоря anchor, когда произошло распознование картинки или плоскости. В зависимости от того, что обнаружили: картинку или плоскость, вызывается тот или иной метод - nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) или nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor), в каждом из которых используется метод добавления выбранной ноды со своей геометрией в ноду обнаруженного объекта (якоря) addNode(_ node: SCNNode, toImageUsingParentNode parentNode: SCNNode).
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    // Вызывается в тот момент, когда поверхность обновилась. То есть когда 2 плоскости - это одна и та же плоскость, и, следовательно, они объединяются.
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor, let planeNode = node.childNodes.first, let geometry = planeNode.geometry as? SCNPlane else { return } // Берется node первой поверхности из двух, которые должны объединиться, и ее геометрия, чтобы затем увеличить ее размеры до размеров объединенной плоскости anchor и позиции ее node.
    
        planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        geometry.width = CGFloat(planeAnchor.extent.x)
        geometry.height = CGFloat(planeAnchor.extent.z)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        if let selectedNode = selectedNode {
            addNode(selectedNode, toImageUsingParentNode: node)
        }
    }
    
    func addNode(_ node: SCNNode, toImageUsingParentNode parentNode: SCNNode) {
        let cloneNode = node.clone()
        
//        if let size = sizeObject {
//            switch size {
//            case .small:
//            case .medium:
//            case .large:
//            case .extraLarge:
//            }
//        }
        
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let planeNode = createPlane(planeAnchor: anchor)
        planeNode.isHidden = !showPlaneOverlay // Необходимо, чтобы сразу при запуске приложения распознаные плоскости не визуализировались (до тех пор, пока showPlaneOverlay не поменяется на true, т.е. пока не вызовется метод togglePlaneVisualization() в Options). А также, чтобы плоскости не визуализировались, при выборе togglePlaneVisualization() в Options, когда showPlaneOverlay меняется на false.
        
        node.addChildNode(planeNode)
        planeNodes.append(planeNode)
    }
    
    func createPlane(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let node = SCNNode()
        
        let width = planeAnchor.extent.x
        let height = planeAnchor.extent.z
        let geometry = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        
        node.geometry = geometry
        node.eulerAngles.x = -Float.pi / 2
        node.opacity = 0.25
        
        return node
    }
}

extension ViewController: OptionsViewControllerDelegate { // Методы delegate, которые определяются во VC (.delegate = self), передаются в Option VC. Они вызываются, уже когда появилось меню Options, при выборе опции в switch option (44 строка).
    
    func objectSelected(node: SCNNode) { // size: Size?) {
        dismiss(animated: true, completion: nil) // Убирается Options VC, поскольку этот метод вызывается в OptionsContainerViewController с помощью delegate в switch option (44 строка), а delegate определен во VC.
        selectedNode = node
//        if let size = size {
//            sizeObject = size
//        }
//        print(sizeObject)
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay = !showPlaneOverlay
    }
    
    func undoLastObject() { // Метод не убирает Options VC.
        if let lastNode = placedNodes.last {
            lastNode.removeFromParentNode()
            placedNodes.removeLast()
        }
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
        
        placedNodes.forEach { (node) in
            node.removeFromParentNode()
            placedNodes.removeFirst()
        }
        print(placedNodes)
        
        planeNodes.forEach { (node) in
            node.removeFromParentNode()
            planeNodes.removeFirst()
        }
        print(planeNodes)
        
        selectedNode = nil
        reloadConfiguration()
    }
    
    func cancel() {
        dismiss(animated: true, completion: nil) // Убирается Options VC, поскольку этот метод вызывается в OptionsContainerViewController с помощью delegate в switch option (44 строка), а delegate определен во VC.
    }
}
