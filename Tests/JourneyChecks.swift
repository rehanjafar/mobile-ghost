import Foundation

@main struct JourneyChecks {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { checks += 1; precondition(condition(),message) }
        let a = GeoPoint(latitude:0,longitude:0)
        let b = GeoPoint(latitude:0,longitude:0.001)
        let c = GeoPoint(latitude:0,longitude:0.002)
        check(abs(a.distance(to:b)-111.195)<0.01,"Great-circle distance")
        check(!GeoPoint(latitude:.nan,longitude:0).isValid,"Reject nonfinite coordinates")
        check(!GeoPoint(latitude:91,longitude:0).isValid,"Reject out-of-range latitude")
        let crossing = GeoPoint(latitude:0,longitude:179).interpolated(to:.init(latitude:0,longitude:-179),fraction:0.5)
        check(abs(crossing.longitude)==180,"Dateline crosses the short way")
        let stops = [JourneyStop(name:"A",point:a,waitSeconds:2,departureSpeed:36),JourneyStop(name:"B",point:b,waitSeconds:3,departureSpeed:72),JourneyStop(name:"C",point:c)]
        let plan = JourneyPlan(stops:stops,legs:[JourneyLeg(points:[a,b]),JourneyLeg(points:[b,c])],mode:"Car")
        check(plan.isValid,"Valid route")
        var cursor = JourneyCursor(plan:plan,speed:5)
        check(cursor.speed==36,"First stop overrides initial speed")
        cursor.advance(seconds:1)
        check(cursor.point==a && cursor.waiting==1,"Wait at first stop")
        cursor.advance(seconds:2)
        check(abs(cursor.meters-10)<0.01,"Move only after wait")
        cursor.advance(seconds:(plan.legs[0].distance-10)/10)
        check(cursor.legIndex==1 && cursor.waiting==3 && cursor.speed==72,"Intermediate wait and departure speed")
        cursor.advance(seconds:2)
        check(cursor.point==b && cursor.waiting==1,"Intermediate stop holds")
        cursor.advance(seconds:2)
        check(abs(cursor.meters-20)<0.01,"New speed after wait")
        cursor.advance(seconds:100)
        check(cursor.finished && cursor.point==c,"Hold final destination")
        let last = cursor.point; cursor.advance(seconds:100)
        check(cursor.point==last,"Finished journey remains fixed")
        var bad = plan; bad.stops[0].departureSpeed = 200
        check(!bad.isValid,"Reject excessive speed")
        bad = plan; bad.stops[0].waitSeconds = -1
        check(!bad.isValid,"Reject negative wait")
        bad = plan; bad.legs = []
        check(!bad.isValid,"Reject missing geometry")
        let zero = JourneyPlan(stops:[JourneyStop(name:"A",point:a),JourneyStop(name:"A",point:a)],legs:[JourneyLeg(points:[a,a])],mode:"Walking")
        var zeroCursor = JourneyCursor(plan:zero,speed:5); zeroCursor.advance(seconds:1)
        check(zeroCursor.finished,"Zero-distance route terminates")
        var live = JourneyCursor(plan:plan,speed:5)
        var proposed = live; proposed.advance(seconds:5)
        check(live.point==a,"Unacknowledged progress does not mutate live cursor")
        live = proposed
        check(live.point != a,"Acknowledged progress can be committed")
        check(BackgroundExecutionPolicy.mayTick(foreground:true,locationActive:false),"Foreground works without background authorization")
        check(BackgroundExecutionPolicy.mayTick(foreground:false,locationActive:true),"Authorized active background session continues")
        check(!BackgroundExecutionPolicy.mayTick(foreground:false,locationActive:false),"Background without active authorization stops")
        check(!BackgroundExecutionPolicy.interrupted(elapsed:1.2),"Ordinary app-switch interval continues")
        check(BackgroundExecutionPolicy.interrupted(elapsed:15),"Actual suspension pauses route")
        check(BackgroundExecutionPolicy.interrupted(elapsed: -1),"Clock rollback does not reverse travel")
        check(BackgroundExecutionPolicy.interrupted(elapsed: .nan),"Nonfinite elapsed time is rejected")
        print("Passed \(checks) journey checks")
    }
}
