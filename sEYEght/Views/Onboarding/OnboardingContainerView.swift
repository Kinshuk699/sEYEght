//
//  OnboardingContainerView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Container that pages through the 3 onboarding steps.
/// After completion, navigates to PermissionsView.
struct OnboardingContainerView: View {
    @State private var currentStep = 0
    @State private var navigateToPermissions = false

    var body: some View {
        Group {
            switch currentStep {
            case 0:
                WelcomeStepView {
                    withAnimation { currentStep = 1 }
                    print("[OnboardingContainer] Step 0 → 1")
                }
            case 1:
                MountPhoneStepView(
                    onNext: {
                        withAnimation { currentStep = 2 }
                        print("[OnboardingContainer] Step 1 → 2")
                    },
                    onBack: {
                        withAnimation { currentStep = 0 }
                        print("[OnboardingContainer] Step 1 → 0")
                    }
                )
            case 2:
                PermissionsIntroStepView(
                    onContinue: {
                        navigateToPermissions = true
                        print("[OnboardingContainer] Step 2 → Permissions")
                    },
                    onBack: {
                        withAnimation { currentStep = 1 }
                        print("[OnboardingContainer] Step 2 → 1")
                    }
                )
            default:
                EmptyView()
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToPermissions) {
            PermissionsView()
        }
    }
}
