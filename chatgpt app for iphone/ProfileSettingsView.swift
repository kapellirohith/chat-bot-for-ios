// ProfileSettingsView.swift
// Lets the user set their name and profile photo
import SwiftUI

struct ProfileSettingsView: View {
    @Binding var profilePhoto: PlatformImage?
    @Binding var userName: String
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    
    private func persistProfile(photo: PlatformImage?, name: String) {
        if let photo = photo, let data = photo.jpegData(compressionQuality: 0.9) {
            UserDefaults.standard.set(data, forKey: "profile_photo")
        } else {
            UserDefaults.standard.removeObject(forKey: "profile_photo")
        }
        UserDefaults.standard.set(name, forKey: "profile_name")
    }
    
    var body: some View {
        Form {
            Section("Profile Photo") {
                HStack(spacing: 12) {
                    if let img = profilePhoto {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 64))
                    }
                    Spacer()
                    Menu("Change Photo") {
                        Button("Choose Photo") {
                            showImagePicker = true
                        }
                        Button("Take Photo") {
                            showCameraPicker = true
                        }
                    }
                    if profilePhoto != nil {
                        Button(role: .destructive) {
                            showImagePicker = false
                            showCameraPicker = false
                            profilePhoto = nil
                        } label: {
                            Text("Remove Photo")
                        }
                    }
                }
            }
            Section("Display Name") {
                TextField("Your Name", text: $userName)
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showImagePicker) {
            #if canImport(UIKit)
            ProfileImagePicker(image: Binding(get: { profilePhoto }, set: { profilePhoto = $0 }), sourceType: .photoLibrary)
            #else
            Text("Image picking is only available on iOS.")
            #endif
        }
        .sheet(isPresented: $showCameraPicker) {
            #if canImport(UIKit)
            ProfileImagePicker(image: Binding(get: { profilePhoto }, set: { profilePhoto = $0 }), sourceType: .camera)
            #else
            Text("Image picking is only available on iOS.")
            #endif
        }
        .onChange(of: profilePhoto) { newPhoto in
            persistProfile(photo: newPhoto, name: userName)
        }
        .onChange(of: userName) { newName in
            persistProfile(photo: profilePhoto, name: newName)
        }
    }
}
