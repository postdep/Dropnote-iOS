//
// Created by Maciej Oczko on 30.01.2016.
// Copyright (c) 2016 Maciej Oczko. All rights reserved.
//

import Foundation
import UIKit
import Swinject
import RxSwift
import RxCocoa
import XCGLogger

protocol NewBrewViewModelType {
    var reloadDataAnimatedSubject: PublishSubject<Bool> { get }
    var failedToCreateNewBrewSubject: PublishSubject<ErrorType> { get }

	var brewContext: StartBrewContext { get }
    var progressIcons: [Asset] { get }

	func configureWithCollectionView(collectionView: UICollectionView)
	func setActiveViewControllerAtIndex(index: Int) -> UIViewController?
	func stepViewController(forIndexPath indexPath: NSIndexPath) -> UIViewController
	func cleanUp() -> Observable<Void>
	func finishBrew() -> Observable<Void>
}

struct StartBrewContext {
    var method: BrewMethod
}

extension NewBrewViewModel: ResolvableContainer { }

final class NewBrewViewModel: NSObject, NewBrewViewModelType {
	private let disposeBag = DisposeBag()

    var resolver: ResolverType?
	let brewContext: StartBrewContext
	let settingsModelController: SequenceSettingsModelControllerType
	let brewModelController: BrewModelControllerType

	let reloadDataAnimatedSubject = PublishSubject<Bool>()
	let failedToCreateNewBrewSubject = PublishSubject<ErrorType>()
    
    var progressIcons: [Asset] {
        return dataSource.progressIcons
    }

	private lazy var dataSource: NewBrewDataSource = {
		guard let resolver = self.resolver else { fatalError("Resolver is missing!") }
		let dataSource = NewBrewDataSource(
				brewContext: self.brewContext,
				brewModelController: self.brewModelController,
				settingsModelController: self.settingsModelController
				)
		dataSource.resolver = resolver
		return dataSource
	}()

    init(brewContext: StartBrewContext,
            settingsModelController: SequenceSettingsModelControllerType,
            newBrewModelController: BrewModelControllerType) {
        self.brewContext = brewContext
        self.settingsModelController = settingsModelController
		self.brewModelController = newBrewModelController
		super.init()
	}

	func configureWithCollectionView(collectionView: UICollectionView) {
		collectionView.dataSource = self
		reloadStepViewControllersWithBrewContext(brewContext, animated: false)
	}

	func setActiveViewControllerAtIndex(currentIndex: Int) -> UIViewController? {
		precondition(dataSource.stepViewControllers.count > 1)
		let activables = [dataSource.stepViewControllers[0], dataSource.stepViewControllers[1]]
			.flatMap { $0 }
			.filter { $0 is Activable }
			.map { $0 as! Activable }

		var activeViewController: UIViewController?
		for (i, var activable) in activables.enumerate() {
			activable.active = currentIndex == i
			if activable.active {
				activeViewController = activable as? UIViewController
			}
		}
		return activeViewController
	}

	func stepViewController(forIndexPath indexPath: NSIndexPath) -> UIViewController {
		return dataSource.stepViewControllers[indexPath.section][indexPath.item]
	}

	func cleanUp() -> Observable<Void> {
		XCGLogger.info("Removing unfinished brew")
		return brewModelController.removeUnfinishedBrew().doOnError {
			XCGLogger.error("Error when removing unfinished brew = \($0)")
		}.map { _ in return () }
	}

	func finishBrew() -> Observable<Void> {
		brewModelController.currentBrew()?.isFinished = true
		return brewModelController.saveBrew().doOnError {
			XCGLogger.error("Error when finishing brew = \($0)")
		}
	}

    private func reloadStepViewControllersWithBrewContext(brewContext: StartBrewContext, animated: Bool) {
		brewModelController
			.createNewBrew(
                withMethod: brewContext.method,
                coffee: nil,
                coffeeMachine: nil)
            .observeOn(MainScheduler.instance)
            .doOnNext { _ in self.dataSource.reloadData() }
            .map { _ in false }
			.subscribe(
				onNext: reloadDataAnimatedSubject.onNext,
				onError: failedToCreateNewBrewSubject.onNext
            )
            .addDisposableTo(disposeBag)
	}
}

extension NewBrewViewModel: UICollectionViewDataSource {

	func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
		return dataSource.stepViewControllers.count
	}

	func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return dataSource.stepViewControllers[section].count
	}

	func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCellWithReuseIdentifier("NewBrewCollectionViewCell", forIndexPath: indexPath) as! NewBrewCollectionViewCell
		let viewController = stepViewController(forIndexPath: indexPath)
		cell.stepView = viewController.view
		return cell
	}
}
