public struct Validations {
    var storage: [Validation]
    var unkeyedStorage: [UnkeyedValidation]
    
    var hasValidations: Bool {
        return !storage.isEmpty || !unkeyedStorage.isEmpty
    }

    public init() {
        self.storage = []
        self.unkeyedStorage = []
    }
    
    public mutating func add<T>(
        _ key: ValidationKey,
        as type: T.Type = T.self,
        is validator: Validator<T> = .valid,
        required: Bool = true
    ) {
        let validation = Validation(key: key, required: required, validator: validator)
        self.storage.append(validation)
    }
    
    public mutating func add(
        _ key: ValidationKey,
        result: ValidatorResult
    ) {
        let validation = Validation(key: key, result: result)
        self.storage.append(validation)
    }

    public mutating func add(
        _ key: ValidationKey,
        required: Bool = true,
        _ nested: (inout Validations) -> ()
    ) {
        var validations = Validations()
        nested(&validations)
        let validation = Validation(nested: key, required: required, keyed: validations)
        self.storage.append(validation)
    }
    
    public mutating func add(
        each key: ValidationKey,
        _ handler: @escaping (Int, inout Validations) -> ()
    ) {
        let validation = Validation(nested: key, unkeyed: handler)
        self.storage.append(validation)
    }
    
    public mutating func addUnkeyed(
        _ handler: @escaping (Int, inout Validations) -> ()
    ) {
        let validation = UnkeyedValidation(handler: handler)
        self.unkeyedStorage.append(validation)
    }
    
    public func validate(request: Request) throws -> ValidationsResult {
        guard hasValidations else {
            return ValidationsResult(results: [])
        }
        
        guard let contentType = request.headers.contentType else {
            throw Abort(.unprocessableEntity)
        }
        guard let body = request.body.data else {
            throw Abort(.unprocessableEntity)
        }
        let contentDecoder = try ContentConfiguration.global.requireDecoder(for: contentType)
        let decoder = try contentDecoder.decode(DecoderUnwrapper.self, from: body, headers: request.headers)
        return try self.validate(decoder.decoder)
    }
    
    public func validate(query: URI) throws -> ValidationsResult {
        guard hasValidations else {
            return ValidationsResult(results: [])
        }
        
        let urlDecoder = try ContentConfiguration.global.requireURLDecoder()
        let decoder = try urlDecoder.decode(DecoderUnwrapper.self, from: query)
        return try self.validate(decoder.decoder)
    }
    
    public func validate(json: String) throws -> ValidationsResult {
        guard hasValidations else {
            return ValidationsResult(results: [])
        }
        
        let decoder = try JSONDecoder().decode(DecoderUnwrapper.self, from: Data(json.utf8))
        return try self.validate(decoder.decoder)
    }
    
    public func validate(_ decoder: Decoder) throws -> ValidationsResult {
        if !unkeyedStorage.isEmpty {
            return validate(try decoder.unkeyedContainer())
        }
        
        if !storage.isEmpty {
            return validate(try decoder.container(keyedBy: ValidationKey.self))
        }
        
        return ValidationsResult(results: [])
    }

    internal func validate(_ container: KeyedDecodingContainer<ValidationKey>) -> ValidationsResult {
        .init(results: storage.map { $0.run(container) })
    }
    
    internal func validate(_ container: UnkeyedDecodingContainer) -> ValidationsResult {
        .init(results: unkeyedStorage.map { $0.run(container) })
    }
}

