//
//  Track.swift
//  Mixpanel
//
//  Created by Yarden Eitan on 6/3/16.
//  Copyright © 2016 Mixpanel. All rights reserved.
//

import Foundation

func += <K, V> (left: inout [K: V], right: [K: V]) {
    for (k, v) in right {
        left.updateValue(v, forKey: k)
    }
}

class Track {
    let apiToken: String
    let lock: ReadWriteLock
    let metadata: SessionMetadata
    
    var isAutomaticEventEnabled: Bool {
        return MixpanelPersistence.loadAutomacticEventsEnabledFlag(token: apiToken)
    }

    init(apiToken: String, lock: ReadWriteLock, metadata: SessionMetadata) {
        self.apiToken = apiToken
        self.lock = lock
        self.metadata = metadata
    }
    
    func track(event: String?,
               properties: Properties? = nil,
               distinctId: String,
               anonymousId: String?,
               userId: String?,
               hadPersistedDistinctId: Bool?,
               epochInterval: Double) {
        var ev = event
        if ev == nil || ev!.isEmpty {
            Logger.info(message: "mixpanel track called with empty event parameter. using 'mp_event'")
            ev = "mp_event"
        }
        if !isAutomaticEventEnabled && ev!.hasPrefix("$ae_") {
            return
        }
        assertPropertyTypes(properties)
        
        let persistedProperties = MixpanelPersistence.sharedInstance.loadEntity(.properties, token: apiToken)
        let timedEvents: InternalProperties = persistedProperties.get(key: "timedEvents", defaultValue: [:])
        
        let superProperties: InternalProperties = InternalProperties()
        
        let epochSeconds = Int(round(epochInterval))
        let eventStartTime = timedEvents[ev!] as? Double
        var p = InternalProperties()
        AutomaticProperties.automaticPropertiesLock.read {
            p += AutomaticProperties.properties
        }
        p["token"] = apiToken
        p["time"] = epochSeconds
        var shadowTimedEvents = timedEvents
        if let eventStartTime = eventStartTime {
            shadowTimedEvents.removeValue(forKey: ev!)
            p["$duration"] = Double(String(format: "%.3f", epochInterval - eventStartTime))
        }
        p["distinct_id"] = distinctId
        if anonymousId != nil {
            p["$device_id"] = anonymousId
        }
        if userId != nil {
            p["$user_id"] = userId
        }
        if hadPersistedDistinctId != nil {
            p["$had_persisted_distinct_id"] = hadPersistedDistinctId
        }
        
        p += superProperties
        if let properties = properties {
            p += properties
        }

        var trackEvent: InternalProperties = ["event": ev!, "properties": p]
        metadata.toDict().forEach { (k, v) in trackEvent[k] = v }
        MixpanelPersistence.sharedInstance.saveEntity(trackEvent, type: .events, token: apiToken)
    }

    func registerSuperProperties(_ properties: Properties,
                                 superProperties: InternalProperties) -> InternalProperties {
        if Mixpanel.mainInstance().hasOptedOutTracking() {
            return superProperties
        }

        var updatedSuperProperties = superProperties
        assertPropertyTypes(properties)
        updatedSuperProperties += properties
        
        return updatedSuperProperties
    }

    func registerSuperPropertiesOnce(_ properties: Properties,
                                     superProperties: InternalProperties,
                                     defaultValue: MixpanelType?) -> InternalProperties {
        if Mixpanel.mainInstance().hasOptedOutTracking() {
            return superProperties
        }

        var updatedSuperProperties = superProperties
        assertPropertyTypes(properties)
        _ = properties.map {
            let val = updatedSuperProperties[$0.key]
            if val == nil ||
                (defaultValue != nil && (val as? NSObject == defaultValue as? NSObject)) {
                updatedSuperProperties[$0.key] = $0.value
            }
        }
        
        return updatedSuperProperties
    }

    func unregisterSuperProperty(_ propertyName: String,
                                 superProperties: InternalProperties) -> InternalProperties {
        var updatedSuperProperties = superProperties
        updatedSuperProperties.removeValue(forKey: propertyName)
        return updatedSuperProperties
    }
        
    func clearSuperProperties(_ superProperties: InternalProperties) -> InternalProperties {
        var updatedSuperProperties = superProperties
        updatedSuperProperties.removeAll()
        return updatedSuperProperties
    }
    
    func updateSuperProperty(_ update: (_ superProperties: inout InternalProperties) -> Void, superProperties: inout InternalProperties) {
        update(&superProperties)
    }

    func time(event: String?, timedEvents: InternalProperties, startTime: Double) -> InternalProperties {
        if Mixpanel.mainInstance().hasOptedOutTracking() {
            return timedEvents
        }
        var updatedTimedEvents = timedEvents
        guard let event = event, !event.isEmpty else {
            Logger.error(message: "mixpanel cannot time an empty event")
            return updatedTimedEvents
        }
        updatedTimedEvents[event] = startTime
        return updatedTimedEvents
    }

    func clearTimedEvents(_ timedEvents: InternalProperties) -> InternalProperties {
        var updatedTimedEvents = timedEvents
        updatedTimedEvents.removeAll()
        return updatedTimedEvents
    }
    
    func clearTimedEvent(event: String?, timedEvents: InternalProperties) -> InternalProperties {
        var updatedTimedEvents = timedEvents
        guard let event = event, !event.isEmpty else {
            Logger.error(message: "mixpanel cannot clear an empty timed event")
            return updatedTimedEvents
        }
        updatedTimedEvents.removeValue(forKey: event)
        return updatedTimedEvents
    }
}
