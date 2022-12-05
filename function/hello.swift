func main(args: Any) -> Any {
    let dict = args as! [String:Any]
    if let name = dict["name"] as? String {
        return [ "greeting" : "Hello \(name)!" ]
    } else {
        return [ "greeting" : "Hello stranger!" ]
    }
}