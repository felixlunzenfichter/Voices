//
//  voicesCloudStorage.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 19.11.20.
//

import Foundation
import Firebase
import FirebaseFirestoreSwift

class VoiceCloudStorage: ObservableObject {
    
    let db = Firestore.firestore()
    @Published var voices: [CloudVoice] = []
    
    init() {
        listenToChangesFirestore()
    }
    
    func listenToChangesFirestore() {
        db.collection("voices")
            .addSnapshotListener { querySnapshot, error in
                guard let snapshot = querySnapshot else {
                    print("Error fetching snapshots: \(error!)")
                    return
                }
                snapshot.documentChanges.forEach { diff in
                    if (diff.type == .added) {
                        self.addVoiceToLocalList(diff)
                    }
                    if (diff.type == .modified) {
                        self.updateVoiceInLocalList(diff)
                    }
                    if (diff.type == .removed) {
                        self.removeVoiceFromLocalList(diff)
                    }
                }
            }
    }
    
    fileprivate func addVoiceToLocalList(_ diff: DocumentChange) {
        let voiceFromFirestore = diff.document.data()
        print("New voice: \(diff.document.data())")
        var voice: CloudVoice
        voice = CloudVoice(transcript: voiceFromFirestore["transcript"] as! String)
        voices.append(voice)
    }
    
    fileprivate func updateVoiceInLocalList(_ diff: DocumentChange) {
        print("Modified voice: \(diff.document.data())")
//        let toggledTodo = diff.document.data()
//        let index = todoList.firstIndex(where: {todo in todo.text == toggledTodo["text"] as? String})
//        todoList[index!].done = toggledTodo["done"] as! Bool
//        objectWillChange.send()
    }
    
    fileprivate func removeVoiceFromLocalList(_ diff: DocumentChange) {
        let todoFromFirestore = diff.document.data()
        print("removed \(todoFromFirestore["transcript"] ?? "default value")")
        #warning("Identify item to be removed by unique identifier.")
        voices.removeAll(where: {todo in todo.transcript == todoFromFirestore["transcipt"] as! String})
    }
    
    func sendVoice(voice: CloudVoice) {
        // Add a new document in collection "cities"
        #warning("identify voice by unique identifier instead of transcript.")
        db.collection("voices").document(voice.transcript).setData([
            "transcript": voice.transcript,
        ]) { err in
            if let err = err {
                print("Error writing document: \(err)")
            } else {
                print("Document successfully written!")
            }
        }
    }

    func deleteVoice(voice: CloudVoice) {
        #warning("identify voice by unique identifier instead of transcript.")
        db.collection("voices").document(voice.transcript).delete() { err in
            if let err = err {
                print("Error removing document: \(err)")
            } else {
                print("Document successfully removed!")
            }
        }
    }
    
    
}
